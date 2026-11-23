import AppKit
import SwiftUI

/// A Lock Screen controller and nothing else.
///
/// There is deliberately no player window and no menu-bar player: the card on the Lock Screen
/// is the whole product. The menu-bar item exists only to reach Settings and to quit, because
/// an `LSUIElement` app with no window needs some way to be reached at all.
@main
struct NoctaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("LyricGlass", systemImage: "waveform") {
            // `SettingsLink`, not a Button calling `showSettingsWindow:`. Sending that action
            // from inside a menu's tracking loop silently does nothing — which is why ⌘,
            // worked (the main menu handles it) while clicking the item did not. SettingsLink
            // exists precisely for opening Settings from a MenuBarExtra.
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit LyricGlass") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }

        Settings {
            SettingsView(model: delegate.model)
                .preferredColorScheme(delegate.model.preferences.appearance.colorScheme)
                // Activation is bound to the window's own lifetime rather than to whatever
                // opened it, so every route in — the menu item, ⌘, — behaves the same. An
                // accessory app's window opens behind everything and cannot take keyboard
                // focus until the policy switches; it switches back on close so no Dock icon
                // lingers.
                .onAppear { delegate.model.activateForWindow() }
                .onDisappear { delegate.model.resignWindowActivation() }
        }
    }
}

/// Owns the model and starts it once AppKit is up.
///
/// `AppModel.start()` creates the Lock Screen panel and registers global shortcuts, which want
/// a fully launched application. It used to hang off the player window's `.task`; with no
/// window left, the launch notification is the honest place for it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}
