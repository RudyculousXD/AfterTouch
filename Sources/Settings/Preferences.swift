import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

/// Surface treatment for the floating player, including its Lock Screen presentation.
enum GlassStyle: String, CaseIterable, Identifiable {
    case liquidGlass, tintedGlass, clearOpaque
    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .tintedGlass: "Tinted Glass"
        case .clearOpaque: "Clear Opaque"
        }
    }

    var subtitle: String {
        switch self {
        case .liquidGlass: "Refractive glass that blends with the artwork"
        case .tintedGlass: "Colored translucent glass with a soft blur"
        case .clearOpaque: "A solid, high-contrast surface"
        }
    }
}

/// Where the Lock Screen controller sits.
///
/// `center` is deliberately absent as a raw option: the middle of the screen is where macOS
/// draws the avatar, password field and Touch ID prompt. See `LockScreenLayout`.
enum LockScreenPosition: String, CaseIterable, Identifiable {
    case top, upperMiddle, bottom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .top:         "Top"
        case .upperMiddle: "Upper middle"
        case .bottom:      "Bottom"
        }
    }
}

enum LockScreenBackdrop: String, CaseIterable, Identifiable {
    case blurredArtwork, softArtwork, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blurredArtwork: "Blurred artwork"
        case .softArtwork: "Soft artwork"
        case .off: "No artwork background"
        }
    }

    var blurRadius: CGFloat {
        switch self {
        case .blurredArtwork: 36
        case .softArtwork: 18
        case .off: 0
        }
    }
}

enum LockScreenPlayerSize: String, CaseIterable, Identifiable {
    case compact, standard, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .compact: 0.60
        case .standard: 1
        case .large: 1.12
        }
    }
}

/// Where transient display and volume feedback appears.
enum SensoryOverlayStyle: String, CaseIterable, Identifiable {
    case notch, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: "Notch"
        case .system: "System"
        }
    }
}

enum SensoryLabelStyle: String, CaseIterable, Identifiable {
    case icon, name
    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "Icon"
        case .name: "Name"
        }
    }
}

/// UserDefaults-backed settings. Stored properties so `@Observable` tracks them; `didSet`
/// persists. No credentials are ever stored here — those go to the Keychain.
@MainActor
@Observable
final class Preferences {
    private static let defaults = UserDefaults.standard

    var autoDetectService: Bool { didSet { Self.defaults.set(autoDetectService, forKey: Key.autoDetect) } }
    var preferredProvider: String { didSet { Self.defaults.set(preferredProvider, forKey: Key.preferredProvider) } }
    var appearance: AppearanceMode { didSet { Self.defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    var glassStyle: GlassStyle { didSet { Self.defaults.set(glassStyle.rawValue, forKey: Key.glassStyle) } }
    var showMenuBarIcon: Bool { didSet { Self.defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    var startMinimized: Bool { didSet { Self.defaults.set(startMinimized, forKey: Key.startMinimized) } }
    var lockScreenEnabled: Bool { didSet { Self.defaults.set(lockScreenEnabled, forKey: Key.lockScreenEnabled) } }
    var lockScreenPosition: LockScreenPosition { didSet { Self.defaults.set(lockScreenPosition.rawValue, forKey: Key.lockScreenPosition) } }
    var lockScreenAllDisplays: Bool { didSet { Self.defaults.set(lockScreenAllDisplays, forKey: Key.lockScreenAllDisplays) } }
    var lockScreenBackdrop: LockScreenBackdrop { didSet { Self.defaults.set(lockScreenBackdrop.rawValue, forKey: Key.backdrop) } }
    var lockScreenPlayerSize: LockScreenPlayerSize { didSet { Self.defaults.set(lockScreenPlayerSize.rawValue, forKey: Key.playerSize) } }
    var lockScreenBackdropDim: Double { didSet { Self.defaults.set(lockScreenBackdropDim, forKey: Key.backdropDim) } }
    var lyricFillEnabled: Bool { didSet { Self.defaults.set(lyricFillEnabled, forKey: Key.lyricFillEnabled) } }
    /// Lyric lookup is a remote request to LRCLIB. The toggle is exposed in Settings.
    var lyricsEnabled: Bool { didSet { Self.defaults.set(lyricsEnabled, forKey: Key.lyricsEnabled) } }
    var brightnessOverlayEnabled: Bool { didSet { Self.defaults.set(brightnessOverlayEnabled, forKey: Key.brightnessOverlayEnabled) } }
    var volumeOverlayEnabled: Bool { didSet { Self.defaults.set(volumeOverlayEnabled, forKey: Key.volumeOverlayEnabled) } }
    var sensoryOverlayStyle: SensoryOverlayStyle { didSet { Self.defaults.set(sensoryOverlayStyle.rawValue, forKey: Key.sensoryOverlayStyle) } }
    var sensoryMatchSongColor: Bool { didSet { Self.defaults.set(sensoryMatchSongColor, forKey: Key.sensoryMatchSongColor) } }
    var sensoryLabelStyle: SensoryLabelStyle { didSet { Self.defaults.set(sensoryLabelStyle.rawValue, forKey: Key.sensoryLabelStyle) } }
    var sensoryOverlayDuration: Double { didSet { Self.defaults.set(sensoryOverlayDuration, forKey: Key.sensoryOverlayDuration) } }

    private enum Key {
        static let autoDetect = "autoDetectService"
        static let lyricsEnabled = "lyricsEnabled"
        static let brightnessOverlayEnabled = "brightnessOverlayEnabled"
        static let volumeOverlayEnabled = "volumeOverlayEnabled"
        static let sensoryOverlayStyle = "sensoryOverlayStyle"
        static let sensoryMatchSongColor = "sensoryMatchSongColor"
        static let sensoryLabelStyle = "sensoryLabelStyle"
        static let sensoryOverlayDuration = "sensoryOverlayDuration"
        static let preferredProvider = "preferredProvider"
        static let appearance = "appearance"
        static let glassStyle = "glassStyle"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let startMinimized = "startMinimized"
        static let lockScreenEnabled = "lockScreenEnabled"
        static let lockScreenPosition = "lockScreenPosition"
        static let lockScreenAllDisplays = "lockScreenAllDisplays"
        static let backdrop = "lockScreenBackdrop"
        static let playerSize = "lockScreenPlayerSize"
        static let backdropDim = "lockScreenBackdropDim"
        static let lyricFillEnabled = "lyricFillEnabled"
    }

    init() {
        let d = Self.defaults
        d.register(defaults: [
            Key.autoDetect: true,
            Key.preferredProvider: ProviderID.spotify.rawValue,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.glassStyle: GlassStyle.tintedGlass.rawValue,
            Key.showMenuBarIcon: true,
            Key.startMinimized: false,
            Key.lockScreenEnabled: true,
            Key.lockScreenPosition: LockScreenPosition.bottom.rawValue,
            Key.lockScreenAllDisplays: true,
            Key.backdrop: LockScreenBackdrop.blurredArtwork.rawValue,
            Key.playerSize: LockScreenPlayerSize.compact.rawValue,
            Key.backdropDim: 0.30,
            Key.lyricFillEnabled: true,
            Key.lyricsEnabled: true,
            Key.brightnessOverlayEnabled: true,
            Key.volumeOverlayEnabled: true,
            Key.sensoryOverlayStyle: SensoryOverlayStyle.notch.rawValue,
            Key.sensoryMatchSongColor: false,
            Key.sensoryLabelStyle: SensoryLabelStyle.icon.rawValue,
            Key.sensoryOverlayDuration: 3.0,
        ])
        autoDetectService = d.bool(forKey: Key.autoDetect)
        preferredProvider = d.string(forKey: Key.preferredProvider) ?? ProviderID.spotify.rawValue
        appearance = AppearanceMode(rawValue: d.string(forKey: Key.appearance) ?? "") ?? .system
        glassStyle = GlassStyle(rawValue: d.string(forKey: Key.glassStyle) ?? "") ?? .tintedGlass
        showMenuBarIcon = d.bool(forKey: Key.showMenuBarIcon)
        startMinimized = d.bool(forKey: Key.startMinimized)
        lockScreenEnabled = d.bool(forKey: Key.lockScreenEnabled)
        lockScreenPosition = LockScreenPosition(rawValue: d.string(forKey: Key.lockScreenPosition) ?? "") ?? .bottom
        lockScreenAllDisplays = d.bool(forKey: Key.lockScreenAllDisplays)
        lockScreenBackdrop = LockScreenBackdrop(rawValue: d.string(forKey: Key.backdrop) ?? "") ?? .blurredArtwork
        lockScreenPlayerSize = LockScreenPlayerSize(rawValue: d.string(forKey: Key.playerSize) ?? "") ?? .compact
        lockScreenBackdropDim = d.double(forKey: Key.backdropDim)
        lyricFillEnabled = d.object(forKey: Key.lyricFillEnabled) as? Bool ?? true
        lyricsEnabled = d.bool(forKey: Key.lyricsEnabled)
        brightnessOverlayEnabled = d.bool(forKey: Key.brightnessOverlayEnabled)
        volumeOverlayEnabled = d.bool(forKey: Key.volumeOverlayEnabled)
        sensoryOverlayStyle = SensoryOverlayStyle(rawValue: d.string(forKey: Key.sensoryOverlayStyle) ?? "") ?? .notch
        sensoryMatchSongColor = d.bool(forKey: Key.sensoryMatchSongColor)
        sensoryLabelStyle = SensoryLabelStyle(rawValue: d.string(forKey: Key.sensoryLabelStyle) ?? "") ?? .icon
        sensoryOverlayDuration = d.double(forKey: Key.sensoryOverlayDuration)
    }

    var preferredProviderID: ProviderID { ProviderID(rawValue: preferredProvider) }
}
