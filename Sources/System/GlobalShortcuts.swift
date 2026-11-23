import KeyboardShortcuts

/// Global hotkeys, backed by Carbon's `RegisterEventHotKey` through the KeyboardShortcuts
/// package.
///
/// Carbon hotkeys need no permission at all — deliberately chosen over a `CGEventTap`, which
/// would require Accessibility access for no added benefit here.
///
/// Nothing is bound by default. The user opts in from Settings, and the recorder warns about
/// conflicts with existing system shortcuts, so we never quietly take over a system binding.
///
/// Known limitation: these do not fire while the screen is locked, because the login window
/// owns the event stream. On the Lock Screen, use the on-screen controls.
extension KeyboardShortcuts.Name {
    static let playPause  = Self("playPause")
    static let nextTrack  = Self("nextTrack")
    static let previous   = Self("previousTrack")
    static let volumeUp   = Self("volumeUp")
    static let volumeDown = Self("volumeDown")
    static let mute       = Self("mute")
}

@MainActor
enum GlobalShortcuts {
    static let volumeStep = 5

    static func register(controller: MediaController) {
        KeyboardShortcuts.onKeyUp(for: .playPause) { controller.togglePlayPause() }
        KeyboardShortcuts.onKeyUp(for: .nextTrack) { controller.next() }
        KeyboardShortcuts.onKeyUp(for: .previous) { controller.previous() }
        KeyboardShortcuts.onKeyUp(for: .mute) { controller.toggleMute() }
        KeyboardShortcuts.onKeyUp(for: .volumeUp) {
            controller.setVolume(min(100, controller.snapshot.volume + volumeStep))
        }
        KeyboardShortcuts.onKeyUp(for: .volumeDown) {
            controller.setVolume(max(0, controller.snapshot.volume - volumeStep))
        }
    }
}
