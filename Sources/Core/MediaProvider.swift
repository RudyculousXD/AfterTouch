import Foundation

/// Extensible provider identity. A struct rather than an enum so additional providers
/// (YouTube Music, Tidal, Amazon Music) can be added without editing this file.
struct ProviderID: RawRepresentable, Hashable, Codable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let spotify    = ProviderID(rawValue: "spotify")
    static let appleMusic = ProviderID(rawValue: "appleMusic")
    static let mock       = ProviderID(rawValue: "mock")
}

enum ProviderError: LocalizedError, Equatable {
    /// The provider's app isn't running. We never launch it just to read state.
    case notRunning(appName: String)
    /// Automation (Apple Events) permission was denied — errAEEventNotPermitted (-1743).
    case automationDenied(appName: String)
    /// The provider does not support this operation; the UI should have disabled it.
    case unsupported(String)
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning(let app):
            return "\(app) isn't running."
        case .automationDenied(let app):
            return "Nocta isn't allowed to control \(app)."
        case .unsupported(let what):
            return "\(what) isn't supported by this music service."
        case .timedOut:
            return "The music app didn't respond."
        case .failed(let message):
            return message
        }
    }
}

/// The single interface the UI talks to. Nothing above this layer knows whether it is driving
/// Spotify, Music.app, or a mock.
protocol MediaProvider: AnyObject {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    /// Whether the backing app is currently running. Implementations MUST NOT launch it.
    func isRunning() -> Bool

    func snapshot() async throws -> PlayerSnapshot

    func play() async throws
    func pause() async throws
    func playPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws

    func seek(to position: TimeInterval) async throws
    func setVolume(_ volume: Int) async throws
    func setMuted(_ muted: Bool) async throws
    func setShuffle(_ enabled: Bool) async throws
    func setRepeat(_ mode: RepeatMode) async throws
    func setFavorite(_ favorite: Bool) async throws
}

/// Optional operations default to a clear error rather than a silent no-op, so a UI bug
/// (offering a control the provider lacks) surfaces loudly instead of looking broken.
extension MediaProvider {
    func seek(to position: TimeInterval) async throws {
        throw ProviderError.unsupported("Seeking")
    }
    func setVolume(_ volume: Int) async throws {
        throw ProviderError.unsupported("Volume control")
    }
    func setMuted(_ muted: Bool) async throws {
        throw ProviderError.unsupported("Mute")
    }
    func setShuffle(_ enabled: Bool) async throws {
        throw ProviderError.unsupported("Shuffle")
    }
    func setRepeat(_ mode: RepeatMode) async throws {
        throw ProviderError.unsupported("Repeat")
    }
    func setFavorite(_ favorite: Bool) async throws {
        throw ProviderError.unsupported("Favourite")
    }
}
