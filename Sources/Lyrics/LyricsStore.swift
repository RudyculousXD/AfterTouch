import Foundation
import Observation

/// Holds the lyrics for whatever is playing, in the same shape as `ArtworkStore`: the view
/// calls `update(for:)` on track change and reads the result.
///
/// Fetching is opt-in. While `isEnabled` is false nothing is requested and no third party is
/// contacted at all, which is the state a fresh install is in.
@MainActor
@Observable
final class LyricsStore {
    enum State: Equatable {
        /// The feature is switched off in Settings.
        case disabled
        case loading
        case instrumental
        /// Timed lines, ready to follow playback.
        case synced(SyncedLyrics)
        /// The database had only unsynced text, so it can be shown but not followed.
        case plain(String)
        case unavailable
    }

    private(set) var state: State = .disabled

    var syncedLyrics: SyncedLyrics? {
        guard case .synced(let lyrics) = state else { return nil }
        return lyrics
    }

    var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                loadedKey = nil
                reload()
            } else {
                inFlight?.cancel()
                inFlight = nil
                state = .disabled
            }
        }
    }

    /// The line to show at `position`, or nil when there is nothing timed to show yet.
    func line(at position: TimeInterval) -> LyricLine? {
        guard case .synced(let lyrics) = state else { return nil }
        return lyrics.line(at: position)
    }

    @ObservationIgnored private let client = LrclibClient()
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    /// The track the current state belongs to, so a repeated poll doesn't refetch.
    @ObservationIgnored private var loadedKey: String?
    @ObservationIgnored private var track: Track?

    func update(for track: Track?) {
        self.track = track
        guard isEnabled else { state = .disabled; return }

        guard let track, !track.title.isEmpty else {
            inFlight?.cancel()
            state = .unavailable
            loadedKey = nil
            return
        }
        guard track.changeKey != loadedKey else { return }
        loadedKey = track.changeKey
        reload()
    }

    private func reload() {
        guard isEnabled, let track else { return }
        inFlight?.cancel()
        state = .loading

        inFlight = Task { [weak self, client] in
            let result = try? await client.lyrics(for: track)
            guard let self, !Task.isCancelled else { return }

            guard let result, !result.isEmpty else {
                self.state = .unavailable
                return
            }
            if result.isInstrumental {
                self.state = .instrumental
            } else if let synced = result.synced {
                self.state = .synced(synced)
            } else if let plain = result.plain, !plain.isEmpty {
                self.state = .plain(plain)
            } else {
                self.state = .unavailable
            }
        }
    }
}
