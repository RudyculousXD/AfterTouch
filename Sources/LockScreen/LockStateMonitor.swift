import AppKit
import CoreGraphics
import Observation

/// Tracks whether the screen is locked, asleep, or belongs to another user.
///
/// Deliberately belt-and-braces, because getting this wrong means the Lock Screen panel is
/// either missing when it should be there or — much worse — lingering after unlock:
///
///  1. `DistributedNotificationCenter` lock/unlock notifications give the fastest signal.
///     These names are undocumented but need no entitlement and no SIP change.
///  2. `NSWorkspace` screen sleep/wake and session active/resign notifications catch display
///     sleep and fast user switching, which the lock notifications don't cover.
///  3. A low-frequency poll of `CGSessionCopyCurrentDictionary()` and `CGDisplayIsAsleep()` —
///     both fully public API — is the authoritative reconciler, so a missed notification
///     self-corrects within a few seconds. Screen sleep needs this as much as lock does:
///     `screensDidWakeNotification` is not guaranteed to arrive, and a missed wake used to
///     strand `screensAsleep` at `true` and hide the panel until the next unlock.
@MainActor
@Observable
final class LockStateMonitor {
    private(set) var isLocked: Bool = false
    private(set) var screensAsleep: Bool = false
    /// False when another user has the session via fast user switching.
    private(set) var sessionIsActive: Bool = true

    /// Called on any change, so the presenter can react immediately rather than polling us.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Called on every reconcile pass, changed or not. Some damage leaves our state correct
    /// and the screen wrong — see `SkyLightLockScreenPresenter.reassert()` — and there is no
    /// notification for it, so the repair has to ride the poll.
    @ObservationIgnored var onReconcile: (() -> Void)?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?

    /// Slow on purpose: the notifications do the real work, this only repairs missed events.
    @ObservationIgnored private let reconcileInterval: Duration = .seconds(5)

    init() {
        isLocked = Self.screenIsLocked()
        observe()
        startReconciling()
    }

    deinit {
        reconcileTask?.cancel()
    }

    /// Authoritative lock state. `CGSessionCopyCurrentDictionary` is public API declared in
    /// `CoreGraphics/CGSession.h`.
    static func screenIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    /// Authoritative display sleep state. `CGDisplayIsAsleep` is public API declared in
    /// `CoreGraphics/CGDirectDisplay.h`.
    static func displaysAreAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    static func sessionIsOnConsole() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return (info["kCGSSessionOnConsoleKey"] as? Bool) ?? true
    }

    private func observe() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(locked: true) }
        })
        observers.append(distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(locked: false) }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(asleep: true) }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(asleep: false) }
        })
        // Fast user switching: another user's session must never see our panel.
        observers.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(sessionActive: false) }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(sessionActive: true) }
        })
    }

    private func startReconciling() {
        reconcileTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.reconcileInterval ?? .seconds(5))
                guard let self else { return }
                let truth = Self.screenIsLocked()
                let onConsole = Self.sessionIsOnConsole()
                let asleep = Self.displaysAreAsleep()
                if truth != self.isLocked { self.set(locked: truth) }
                if onConsole != self.sessionIsActive { self.set(sessionActive: onConsole) }
                if asleep != self.screensAsleep { self.set(asleep: asleep) }
                self.onReconcile?()
            }
        }
    }

    private func set(locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
        onChange?()
    }

    private func set(asleep: Bool) {
        guard screensAsleep != asleep else { return }
        screensAsleep = asleep
        onChange?()
    }

    private func set(sessionActive: Bool) {
        guard sessionIsActive != sessionActive else { return }
        sessionIsActive = sessionActive
        onChange?()
    }

    /// The polling cadence the media controller should use for the current state.
    var pollingContext: PollingContext {
        if screensAsleep { return .asleep }
        if isLocked && sessionIsActive { return .lockScreen }
        return .background
    }

    /// Whether the Lock Screen controller should currently be visible.
    var shouldShowLockScreenUI: Bool {
        isLocked && sessionIsActive && !screensAsleep
    }
}
