import Foundation
import Observation

/// How the app is currently being observed, which decides how hard we poll.
/// Apple Events are relatively expensive, so we only poll fast when someone is looking.
enum PollingContext: Equatable {
    /// Screen locked and our Lock Screen panel is on display — must feel live.
    case lockScreen
    /// A window or the menu-bar popover is visible.
    case foreground
    /// Running, but nothing of ours is on screen.
    case background
    /// Displays asleep. Stop entirely.
    case asleep

    var interval: TimeInterval? {
        switch self {
        case .lockScreen: return 1.0
        case .foreground: return 1.0
        case .background: return 3.0
        case .asleep:     return nil
        }
    }
}

enum ProviderStatus: Equatable {
    case connected
    case nothingPlaying
    case appNotRunning(String)
    case permissionDenied(String)
    case error(String)

    var isHealthy: Bool {
        self == .connected || self == .nothingPlaying
    }
}

/// The single source of truth the whole UI observes.
///
/// Owns provider selection (manual or automatic), the polling loop, and command dispatch.
/// Deliberately knows nothing about *how* a provider talks to its app.
@MainActor
@Observable
final class MediaController {
    private(set) var snapshot: PlayerSnapshot = .idle
    private(set) var status: ProviderStatus = .nothingPlaying
    private(set) var activeProviderID: ProviderID?

    /// When true, we follow whichever supported app is actually playing.
    var autoDetect: Bool = true {
        didSet { Task { await refreshNow() } }
    }

    /// Used when `autoDetect` is off.
    var preferredProviderID: ProviderID = .spotify {
        didSet { Task { await refreshNow() } }
    }

    var pollingContext: PollingContext = .foreground {
        didSet {
            guard pollingContext != oldValue else { return }
            restartPolling()
        }
    }

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Remembers the last provider that was genuinely playing, so a brief pause doesn't
    /// bounce the UI to the other service.
    @ObservationIgnored private var lastPlayingProviderID: ProviderID?

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    var activeProvider: MediaProvider? {
        activeProviderID.flatMap { registry.provider(for: $0) }
    }

    var capabilities: ProviderCapabilities {
        activeProvider?.capabilities ?? []
    }

    var activeProviderName: String {
        activeProviderID.map { registry.displayName(for: $0) } ?? "No service"
    }

    // MARK: - Polling

    func start() {
        restartPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func restartPolling() {
        pollTask?.cancel()
        guard let interval = pollingContext.interval else { pollTask = nil; return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// One poll cycle: choose a provider, read it, publish the result.
    func refreshNow() async {
        let selection = await resolveProvider()
        guard let provider = selection.provider else { return }
        activeProviderID = provider.id
        do {
            // Auto-detection already sampled providers to learn which one is playing.
            // Reuse the selected sample instead of issuing a second Apple Events round trip
            // (and, for Spotify, repeating the API enrichment) in the same poll cycle.
            let fresh: PlayerSnapshot
            if let observed = selection.snapshot {
                fresh = observed
            } else {
                fresh = try await provider.snapshot()
            }
            snapshot = fresh
            if fresh.status == .playing { lastPlayingProviderID = provider.id }
            status = (fresh.track == nil) ? .nothingPlaying : .connected
        } catch let error as ProviderError {
            apply(error, for: provider)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Picks the provider to drive this cycle.
    ///
    /// In auto mode we only ever *ask* apps that are already running — never launching one
    /// merely to read its state — and prefer whichever is actually playing.
    private func resolveProvider() async -> (provider: MediaProvider?, snapshot: PlayerSnapshot?) {
        guard autoDetect else {
            let provider = registry.provider(for: preferredProviderID)
            if let provider, !provider.isRunning() {
                activeProviderID = provider.id
                status = .appNotRunning(registry.displayName(for: provider.id))
                snapshot = .idle
            }
            return (provider, nil)
        }

        let running = registry.selectableEntries
            .compactMap { registry.provider(for: $0.id) }
            .filter { $0.isRunning() }

        guard !running.isEmpty else {
            activeProviderID = lastPlayingProviderID ?? preferredProviderID
            status = .nothingPlaying
            snapshot = .idle
            return (nil, nil)
        }

        var observations: [(provider: MediaProvider, snapshot: PlayerSnapshot?)] = []
        for provider in running {
            let observed = try? await provider.snapshot()
            observations.append((provider, observed))
            if let observed, observed.status == .playing {
                return (provider, observed)
            }
        }
        // Nothing is playing: stay with whatever we were last on, if it's still running.
        if let last = lastPlayingProviderID,
           let previous = observations.first(where: { $0.provider.id == last }) {
            return (previous.provider, previous.snapshot)
        }
        guard let first = observations.first else { return (nil, nil) }
        return (first.provider, first.snapshot)
    }

    private func apply(_ error: ProviderError, for provider: MediaProvider) {
        switch error {
        case .notRunning(let app):
            status = .appNotRunning(app)
            snapshot = .idle
        case .automationDenied(let app):
            status = .permissionDenied(app)
        case .timedOut:
            status = .error("\(provider.displayName) didn't respond.")
        case .unsupported(let what):
            status = .error("\(what) isn't supported by \(provider.displayName).")
        case .failed(let message):
            status = .error(message)
        }
    }

    // MARK: - Commands
    //
    // Each command applies an optimistic local change so the UI reacts instantly, then
    // re-reads the provider to reconcile with the truth.

    private func perform(
        optimistic: (inout PlayerSnapshot) -> Void = { _ in },
        _ action: @escaping (MediaProvider) async throws -> Void
    ) {
        guard let provider = activeProvider else { return }
        optimistic(&snapshot)
        Task {
            do {
                try await action(provider)
                await refreshNow()
            } catch let error as ProviderError {
                apply(error, for: provider)
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    func togglePlayPause() {
        perform(optimistic: { snap in
            snap.position = snap.interpolatedPosition()
            snap.capturedAt = Date()
            snap.status = snap.status == .playing ? .paused : .playing
        }) { try await $0.playPause() }
    }

    func next() {
        perform(optimistic: { $0.position = 0; $0.capturedAt = Date() }) {
            try await $0.nextTrack()
        }
    }

    func previous() {
        perform(optimistic: { $0.position = 0; $0.capturedAt = Date() }) {
            try await $0.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        perform(optimistic: { $0.position = position; $0.capturedAt = Date() }) {
            try await $0.seek(to: position)
        }
    }

    func setVolume(_ volume: Int) {
        perform(optimistic: { $0.volume = volume; $0.isMuted = volume == 0 }) {
            try await $0.setVolume(volume)
        }
    }

    func toggleMute() {
        let target = !snapshot.isMuted
        perform(optimistic: { $0.isMuted = target }) { try await $0.setMuted(target) }
    }

    func toggleShuffle() {
        let target = !snapshot.isShuffling
        perform(optimistic: { $0.isShuffling = target }) { try await $0.setShuffle(target) }
    }

    /// Cycles off → all → one → off, skipping `.one` for providers that have no such state.
    /// Spotify is one: it would accept the command, report `.all` back on the next poll, and
    /// leave the button flicking between two positions while appearing to offer three.
    func cycleRepeat() {
        let target = RepeatMode.next(
            after: snapshot.repeatMode,
            hasRepeatOne: capabilities.contains(.repeatOne)
        )
        perform(optimistic: { $0.repeatMode = target }) { try await $0.setRepeat(target) }
    }

    func toggleFavorite() {
        let target = !(snapshot.track?.isFavorite ?? false)
        perform(optimistic: { $0.track?.isFavorite = target }) {
            try await $0.setFavorite(target)
        }
    }
}
