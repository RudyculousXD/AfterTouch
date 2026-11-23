import Foundation

enum PlaybackStatus: Equatable {
    case stopped
    case playing
    case paused

    var isPlaying: Bool { self == .playing }
}

enum RepeatMode: String, CaseIterable, Equatable {
    case off, one, all

    /// The next position when the repeat control is pressed: off → all → one → off.
    ///
    /// `.one` is skipped entirely for providers that have no such state, rather than being
    /// offered and then silently corrected on the next poll. Spotify is the case in point —
    /// its scripting dictionary exposes `repeating` as a plain boolean.
    static func next(after current: RepeatMode, hasRepeatOne: Bool) -> RepeatMode {
        switch current {
        case .off: return .all
        case .all: return hasRepeatOne ? .one : .off
        case .one: return .off
        }
    }
}

/// An immutable reading of a provider's state at a single instant.
///
/// `position` is only valid as of `capturedAt`. The UI interpolates between polls rather than
/// asking the music app for the position many times a second — the same model
/// `MPNowPlayingInfoCenter` uses.
struct PlayerSnapshot: Equatable {
    var track: Track?
    var status: PlaybackStatus
    var position: TimeInterval
    var volume: Int          // 0...100, matching both scripting dictionaries
    var isMuted: Bool
    var isShuffling: Bool
    var repeatMode: RepeatMode
    var capturedAt: Date

    static let idle = PlayerSnapshot(
        track: nil,
        status: .stopped,
        position: 0,
        volume: 50,
        isMuted: false,
        isShuffling: false,
        repeatMode: .off,
        capturedAt: .distantPast
    )

    /// Position extrapolated to `date`, clamped to the track duration.
    /// Only advances while actually playing.
    func interpolatedPosition(at date: Date = Date()) -> TimeInterval {
        guard status == .playing else { return position }
        let elapsed = max(0, date.timeIntervalSince(capturedAt))
        let projected = position + elapsed
        guard let duration = track?.duration, duration > 0 else { return projected }
        return min(projected, duration)
    }
}
