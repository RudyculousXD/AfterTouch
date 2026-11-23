import AppKit
import SwiftUI

/// The window that appears over the Lock Screen.
///
/// ## Safety design
/// This is a **non-activating panel that can never become key or main**. Mouse events reach
/// it; keyboard events never do. That makes capturing a password structurally impossible
/// rather than merely unimplemented, and means we can't steal focus from the password field
/// or block the user from unlocking.
///
/// This is a deliberate divergence from SkyLightWindow, which sets `canBecomeKey = true`.
/// The Stage 1 spike confirmed clicks still land with `canBecomeKey == false`.
///
/// ## Sizing
/// The panel is sized to the card, not to the screen. The spike used a full-screen transparent
/// panel and — because `NSView.hitTest` reports a hit anywhere inside bounds regardless of
/// transparency — it swallowed clicks meant for apps underneath. Sizing to content avoids the
/// problem entirely instead of fighting hit-testing.
final class LockScreenPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false

        // Public AppKit API since macOS 10.5. Apple's own header: "controls whether the
        // receiver is permitted onscreen before the user has logged in."
        canBecomeVisibleWithoutLogin = true

        // Above everything, including full-screen apps. The SkyLight space is what actually
        // gets us over the lock screen shield; this keeps us on top within that space.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        // Fading is driven by the presenter on lock/unlock transitions.
        alphaValue = 0
    }

    /// The safety guarantee. Do not relax these without re-running the Lock Screen tests.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Belt and braces: even if something upstream tried to make us key, refuse.
    override func makeKey() {}
}

/// Hosting view that declines to intercept clicks outside the card itself.
///
/// The panel is sized to the *expanded* card so it never has to be resized mid-animation, and
/// the collapsed bar fills only part of it. Without this, every transparent pixel around the
/// card would be a dead zone that swallowed clicks meant for whatever is underneath — the same
/// defect the Stage 1 spike hit with a full-screen panel, since `NSView.hitTest` reports a hit
/// anywhere inside bounds regardless of transparency.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// The card's current rect, in top-left coordinates within the panel. Supplied by the
    /// presenter, which asks the shared card state whether it is expanded. Returning nil
    /// treats the whole view as interactive.
    var interactiveRect: (() -> CGRect?)?

    /// `point` arrives in the superview's coordinate system, so it is converted rather than
    /// compared to `bounds` directly.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let rect = interactiveRect?() else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        // A little slop so the rounded corners and the card's shadow edge stay clickable.
        var target = rect.insetBy(dx: -4, dy: -4)
        if !isFlipped { target.origin.y = bounds.height - target.maxY }
        guard target.contains(local) else { return nil }
        return super.hitTest(point)
    }
}
