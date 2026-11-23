import AppKit
import Foundation

/// A fully working in-memory provider. Exists so the entire UI — including the Lock Screen
/// panel — can be built, reviewed and tested without Spotify, Music.app, or any permission
/// prompt. Also backs the unit tests, which need deterministic behaviour.
final class MockProvider: MediaProvider {
    let id = ProviderID.mock
    let displayName = "Demo"
    /// Deliberately advertises everything, so UI capability-gating is exercised by the real
    /// providers rather than accidentally hidden here.
    let capabilities: ProviderCapabilities = [
        .seek, .volume, .nativeMute, .shuffle, .repeatMode, .repeatOne, .favorite,
    ]

    private var tracks: [Track]
    private var index = 0
    private var status: PlaybackStatus = .playing
    private var position: TimeInterval = 0
    private var lastTick = Date()
    private var volume = 65
    private var muted = false
    private var shuffling = false
    private var repeatMode: RepeatMode = .off
    private var favorites: Set<String> = []

    /// When true, `snapshot()` advances position by real elapsed time. Tests turn this off
    /// so they can drive the clock themselves.
    private let advancesWithWallClock: Bool

    init(tracks: [Track]? = nil, advancesWithWallClock: Bool = true) {
        self.tracks = tracks ?? MockProvider.demoTracks
        self.advancesWithWallClock = advancesWithWallClock
    }

    func isRunning() -> Bool { true }

    private var currentTrack: Track? {
        guard tracks.indices.contains(index) else { return nil }
        var track = tracks[index]
        track.isFavorite = favorites.contains(track.id)
        return track
    }

    private func advanceClock() {
        guard advancesWithWallClock else { return }
        let now = Date()
        defer { lastTick = now }
        guard status == .playing else { return }
        position += now.timeIntervalSince(lastTick)
        if let duration = currentTrack?.duration, position >= duration {
            position = 0
            index = (index + 1) % max(tracks.count, 1)
        }
    }

    func snapshot() async throws -> PlayerSnapshot {
        advanceClock()
        return PlayerSnapshot(
            track: currentTrack,
            status: status,
            position: position,
            volume: muted ? 0 : volume,
            isMuted: muted,
            isShuffling: shuffling,
            repeatMode: repeatMode,
            capturedAt: Date()
        )
    }

    func play() async throws { advanceClock(); status = .playing }
    func pause() async throws { advanceClock(); status = .paused }
    func playPause() async throws {
        advanceClock()
        status = (status == .playing) ? .paused : .playing
    }

    func nextTrack() async throws {
        advanceClock()
        index = (index + 1) % max(tracks.count, 1)
        position = 0
    }

    func previousTrack() async throws {
        advanceClock()
        // Match the convention both real apps use: restart the track if we're past the
        // opening seconds, otherwise step back.
        if position > 3 {
            position = 0
        } else {
            index = (index - 1 + tracks.count) % max(tracks.count, 1)
            position = 0
        }
    }

    func seek(to position: TimeInterval) async throws {
        advanceClock()
        self.position = max(0, min(position, currentTrack?.duration ?? position))
    }

    func setVolume(_ volume: Int) async throws {
        self.volume = max(0, min(100, volume))
        if self.volume > 0 { muted = false }
    }

    func setMuted(_ muted: Bool) async throws { self.muted = muted }
    func setShuffle(_ enabled: Bool) async throws { shuffling = enabled }
    func setRepeat(_ mode: RepeatMode) async throws { repeatMode = mode }

    func setFavorite(_ favorite: Bool) async throws {
        guard let id = currentTrack?.id else { return }
        if favorite { favorites.insert(id) } else { favorites.remove(id) }
    }
}

extension MockProvider {
    /// Artwork is generated rather than shipped, so there are no third-party image rights in
    /// the repo and the gradient still exercises the artwork-derived accent colour path.
    static func placeholderArtwork(_ colors: [NSColor], seed: String) -> ArtworkSource? {
        let size = NSSize(width: 600, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: colors)
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)
        let initial = String(seed.prefix(1)).uppercased()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 260, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.22),
        ]
        let text = NSAttributedString(string: initial, attributes: attrs)
        let bounds = text.size()
        text.draw(at: NSPoint(x: (size.width - bounds.width) / 2,
                              y: (size.height - bounds.height) / 2))
        image.unlockFocus()
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return .data(png)
    }

    static let demoTracks: [Track] = [
        Track(
            id: "mock-1",
            title: "Midnight Corridor",
            artist: "Vela Sound",
            album: "Long Nights",
            duration: 222,
            artwork: placeholderArtwork(
                [NSColor(srgbRed: 0.42, green: 0.20, blue: 0.72, alpha: 1),
                 NSColor(srgbRed: 0.11, green: 0.36, blue: 0.78, alpha: 1)],
                seed: "Midnight Corridor")
        ),
        Track(
            id: "mock-2",
            title: "A Considerably Longer Song Title That Should Truncate Gracefully",
            artist: "The Very Long Artist Name Collective",
            album: "Edge Cases",
            duration: 187,
            artwork: placeholderArtwork(
                [NSColor(srgbRed: 0.86, green: 0.28, blue: 0.32, alpha: 1),
                 NSColor(srgbRed: 0.94, green: 0.60, blue: 0.20, alpha: 1)],
                seed: "A Considerably Longer")
        ),
        Track(
            id: "mock-3",
            title: "No Artwork Here",
            artist: "Missing Art",
            album: "Fallbacks",
            duration: 154,
            artwork: nil    // exercises the missing-artwork UI state
        ),
    ]
}
