import AppKit
import OSLog
import SwiftUI

/// Manages one Lock Screen panel per display, moves them into the SkyLight space, and fades
/// them in and out as the Mac locks and unlocks.
///
/// PRIVATE API BOUNDARY — this and `SkyLightBridge` are the only files that know SkyLight
/// exists.
@MainActor
final class SkyLightLockScreenPresenter: LockScreenPresenting {
    private(set) var availability: LockScreenAvailability = .available

    private let bridge: SkyLightBridge
    private let content: (NSScreen, LockScreenLayout.Metrics, LockScreenCardState) -> AnyView
    private let preferences: Preferences

    private var panels: [LockScreenPanel] = []
    /// One per panel: each display's card expands independently.
    private var cardStates: [LockScreenCardState] = []
    private var isVisible = false
    private var screenObserver: NSObjectProtocol?
    private var retryTask: Task<Void, Never>?

    private let log = Logger(subsystem: "app.nocta.Nocta", category: "lockscreen")

    /// How long after a reported wake to keep re-asserting. Short, bounded and front-loaded:
    /// the window server settles in well under a second, and anything still broken after two
    /// is the reconcile poll's problem, not a reason to spin.
    private static let retryDelays: [Duration] = [
        .milliseconds(120), .milliseconds(300), .milliseconds(600), .seconds(1.2), .seconds(2),
    ]

    /// Long enough to read as a deliberate reveal rather than a pop, short enough that the
    /// controls are usable almost immediately after the lock screen appears.
    private let fadeDuration: TimeInterval = 0.35

    init(
        bridge: SkyLightBridge,
        content: @escaping (NSScreen, LockScreenLayout.Metrics, LockScreenCardState) -> AnyView,
        preferences: Preferences
    ) {
        self.bridge = bridge
        self.content = content
        self.preferences = preferences

        // Displays can be attached, detached or rearranged while we're running.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigure() }
        }
    }

    deinit {
        retryTask?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible

        if visible {
            buildPanelsIfNeeded()
            present()
            animate(to: 1)
        } else {
            retryTask?.cancel()
            retryTask = nil
            animate(to: 0) { [weak self] in
                // Fully order out so nothing of ours can linger over another user's session.
                self?.panels.forEach { $0.orderOut(nil) }
                // An unlock should never leave the card expanded for the next lock.
                self?.cardStates.forEach { $0.collapse() }
            }
        }
    }

    func reconfigure() {
        tearDownPanels()
        guard isVisible else { return }
        buildPanelsIfNeeded()
        present()
        panels.forEach { $0.alphaValue = 1 }
    }

    /// Put the panel back over the lock screen without rebuilding anything.
    ///
    /// The window server can drop us silently: sleeping and waking the displays while locked
    /// re-shows the lock screen's own spaces and leaves ours hidden. Nothing about *our* state
    /// changes when that happens — `isVisible` is still true, the panels are still ordered
    /// front — so `setVisible` early-returns and the card stays gone until the next unlock.
    /// This is the repair. It is idempotent, so callers can run it on a timer.
    func reassert(_ repair: LockScreenRepair) {
        guard isVisible, !panels.isEmpty else { return }
        log.debug("re-asserting lock screen panel (\(repair.rawValue, privacy: .public))")
        present()
        panels.forEach { $0.alphaValue = 1 }
    }

    /// Re-assert now, then again on a short schedule.
    ///
    /// One repair at the moment of wake is not enough. The wake notification lands *before*
    /// loginwindow has finished rebuilding the lock screen's shown spaces, so an immediate
    /// re-show gets undone a fraction of a second later and the card stays missing until the
    /// reconcile poll notices seconds afterwards. Repeating briefly wins the race whichever
    /// order the two land in, and then stops.
    func reassertPersistently() {
        reassert(.stateChange)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            for delay in Self.retryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.reassert(.retry)
            }
        }
    }

    /// Show the space, order the panels up, and re-adopt them. Alpha is left alone: showing
    /// fades in, re-asserting must not restart a fade that already finished.
    private func present() {
        guard !LockScreenPreview.isEnabled else {
            panels.forEach { $0.orderFrontRegardless() }
            return
        }
        bridge.showSpace()
        for panel in panels {
            panel.orderFrontRegardless()
            bridge.adopt(panel)
        }
    }

    // MARK: - Panels

    private func targetScreens() -> [NSScreen] {
        guard preferences.lockScreenAllDisplays else {
            return NSScreen.main.map { [$0] } ?? []
        }
        return NSScreen.screens
    }

    private func buildPanelsIfNeeded() {
        guard panels.isEmpty else { return }

        for screen in targetScreens() {
            let position = preferences.lockScreenPosition
            let metrics = LockScreenLayout.metrics(
                for: position, in: screen.frame, lyricsEnabled: preferences.lyricsEnabled
            )
            // The transparent panel spans the display so the artwork wash can cover the
            // central band. PassthroughHostingView keeps every pixel outside the player
            // click-through; the clock and authentication bands remain visually clear.
            let frame = screen.frame
            let cardFrame = LockScreenLayout.frame(for: position, in: screen.frame, metrics: metrics)
            let compactScale = preferences.lockScreenPlayerSize.scale
            let cardState = LockScreenCardState()
            let panel = LockScreenPanel(contentRect: frame)
            let hosting = PassthroughHostingView(rootView: content(screen, metrics, cardState))
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            hosting.autoresizingMask = [.width, .height]
            // Only the card's own pixels take clicks; the rest of the panel passes through.
            hosting.interactiveRect = { [weak cardState] in
                let expanded = cardState?.isExpanded ?? false
                let cardRect = metrics.cardRect(expanded: expanded)
                let playerScale: CGFloat = expanded ? 1 : compactScale
                let originX = cardFrame.minX - screen.frame.minX
                let originY = screen.frame.maxY - cardFrame.maxY
                let playerRect = CGRect(
                    x: originX + (cardRect.minX - metrics.panelSize.width / 2) * playerScale + metrics.panelSize.width / 2,
                    y: originY + (cardRect.minY - metrics.panelSize.height / 2) * playerScale + metrics.panelSize.height / 2,
                    width: cardRect.width * playerScale,
                    height: cardRect.height * playerScale
                )
                // The screen-corner Lyrics/close pill remains available even when the card is
                // collapsed and its hit region has moved back to the compact player.
                return playerRect.union(CGRect(x: 34, y: 22, width: 84, height: 48))
            }
            panel.contentView = hosting
            panel.setFrame(frame, display: false)

            if !LockScreenPreview.isEnabled, !bridge.adopt(panel) {
                availability = .failed("the panel could not be moved to the Lock Screen space")
            }
            panels.append(panel)
            cardStates.append(cardState)
        }
    }

    private func tearDownPanels() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()
        cardStates.removeAll()
    }

    private func animate(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for panel in panels {
                panel.animator().alphaValue = alpha
            }
        } completionHandler: {
            completion?()
        }
    }
}
