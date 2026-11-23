import AppKit
import SwiftUI

/// Why the Lock Screen feature is or isn't available. Surfaced in Settings so the user is
/// told plainly instead of finding a feature that quietly does nothing.
enum LockScreenAvailability: Equatable {
    case available
    /// The private windowing APIs this depends on are absent — expected on a future macOS.
    case unsupportedOS
    /// The APIs exist but creating the space failed.
    case failed(String)

    var isAvailable: Bool { self == .available }

    var explanation: String {
        switch self {
        case .available:
            return "Lock Screen controls are active."
        case .unsupportedOS:
            return "Lock Screen controls aren't supported on this version of macOS."
        case .failed(let reason):
            return "Lock Screen controls couldn't start: \(reason)"
        }
    }
}

/// Development aid: with `NOCTA_PREVIEW_LOCK_SCREEN=1` the card is shown over the desktop
/// while the Mac is unlocked, and is *not* moved into the Lock Screen space — that space is
/// invisible until the Mac locks, which is what made iterating on the design slow.
enum LockScreenPreview {
    static let isEnabled =
        ProcessInfo.processInfo.environment["NOCTA_PREVIEW_LOCK_SCREEN"] == "1"
}

/// What prompted a re-assert. Logged, so a Lock Screen that repairs itself slowly can be told
/// apart from one that repairs itself immediately without guessing — the difference is whether
/// `wake` did the work or `poll` had to.
enum LockScreenRepair: String {
    /// Lock, unlock, display sleep or display wake was reported.
    case stateChange
    /// A follow-up of `stateChange`, in case the window server had not settled yet.
    case retry
    /// The reconcile poll, which is the backstop when nothing was reported at all.
    case poll
}

/// The interface the app uses. Everything above this line is unaware that private APIs exist.
@MainActor
protocol LockScreenPresenting: AnyObject {
    var availability: LockScreenAvailability { get }
    /// Show or hide the controller. Safe to call repeatedly with the same value.
    func setVisible(_ visible: Bool)
    /// Rebuild panels, e.g. after a display is attached or the position preference changes.
    func reconfigure()
    /// Re-assert an already-visible controller against a window server that may have dropped
    /// it. Cheap and idempotent — safe to call on a timer.
    func reassert(_ repair: LockScreenRepair)
    /// Re-assert now, and again a few times over the next couple of seconds.
    func reassertPersistently()
}

/// Picks an implementation by probing for the private symbols at launch rather than by
/// checking a version number, so a future macOS that removes them degrades gracefully instead
/// of crashing — the failure mode reported against Atoll on macOS 27 betas.
@MainActor
enum LockScreenPresenterFactory {
    static func make(
        content: @escaping (NSScreen, LockScreenLayout.Metrics, LockScreenCardState) -> AnyView,
        preferences: Preferences
    ) -> LockScreenPresenting {
        guard SkyLightBridge.isAvailable, let bridge = SkyLightBridge() else {
            return UnsupportedLockScreenPresenter(
                reason: SkyLightBridge.isAvailable
                    ? .failed("the window server rejected the request")
                    : .unsupportedOS
            )
        }
        return SkyLightLockScreenPresenter(
            bridge: bridge, content: content, preferences: preferences
        )
    }
}

/// Used when the technique isn't available. Does nothing, loudly.
@MainActor
final class UnsupportedLockScreenPresenter: LockScreenPresenting {
    let availability: LockScreenAvailability

    init(reason: LockScreenAvailability) {
        availability = reason
    }

    func setVisible(_ visible: Bool) {}
    func reconfigure() {}
    func reassert(_ repair: LockScreenRepair) {}
    func reassertPersistently() {}
}
