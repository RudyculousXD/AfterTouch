import Foundation

/// Central place where providers are declared. Adding YouTube Music, Tidal or Amazon Music
/// later means adding one entry here and one file in `Providers/` — no UI changes.
@MainActor
final class ProviderRegistry {
    struct Entry {
        let id: ProviderID
        let displayName: String
        /// Bundle identifier of the app this provider drives, if any. Used to check whether
        /// the app is running *without* launching it.
        let bundleIdentifier: String?
        let make: () -> MediaProvider
        /// Hidden from the service picker (the mock is a development aid, not a service).
        let isSelectable: Bool
    }

    private(set) var entries: [Entry]
    private var instances: [ProviderID: MediaProvider] = [:]

    init(entries: [Entry]) {
        self.entries = entries
    }

    static func standard(spotifyAuth: SpotifyAuth? = nil) -> ProviderRegistry {
        ProviderRegistry(entries: [
            Entry(
                id: .spotify,
                displayName: "Spotify",
                bundleIdentifier: SpotifyProvider.bundleIdentifier,
                make: { SpotifyProvider(auth: spotifyAuth) },
                isSelectable: true
            ),
            Entry(
                id: .appleMusic,
                displayName: "Apple Music",
                bundleIdentifier: AppleMusicProvider.bundleIdentifier,
                make: { AppleMusicProvider() },
                isSelectable: true
            ),
            Entry(
                id: .mock,
                displayName: "Demo",
                bundleIdentifier: nil,
                make: { MockProvider() },
                isSelectable: false
            ),
        ])
    }

    var selectableEntries: [Entry] { entries.filter(\.isSelectable) }

    func entry(for id: ProviderID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Providers are cached so state such as Spotify's emulated-mute previous volume survives
    /// across polls and provider switches.
    func provider(for id: ProviderID) -> MediaProvider? {
        if let existing = instances[id] { return existing }
        guard let entry = entry(for: id) else { return nil }
        let made = entry.make()
        instances[id] = made
        return made
    }

    func displayName(for id: ProviderID) -> String {
        entry(for: id)?.displayName ?? id.rawValue
    }
}
