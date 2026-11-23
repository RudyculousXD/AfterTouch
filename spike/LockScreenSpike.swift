// LockScreenSpike — throwaway Stage 1 de-risking spike for Nocta.
//
// Answers three questions on this exact macOS build:
//   Q1  Does a window placed in a SkyLight space at absolute level 400 render above the lock screen?
//   Q2  Does a CLICK on that window register while the Mac is locked?
//   Q3  Does a non-activating panel leave password entry completely unaffected?
//
// Everything is written to spike.log with a timestamp and the lock state at that moment,
// so the answers are objective rather than remembered.

import AppKit
import Foundation

// MARK: - Logging

let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("spike.log")

let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func log(_ message: String) {
    let line = "[\(logFormatter.string(from: Date()))] [locked=\(screenIsLocked() ? "YES" : "no ")] \(message)\n"
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

/// Authoritative lock-state check. Public CoreGraphics API (CGSession.h).
func screenIsLocked() -> Bool {
    guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (info["CGSSessionScreenIsLocked"] as? Int) == 1
}

// MARK: - SkyLight bridge (PRIVATE API — isolated here)

/// Space absolute levels. 300 is the lock screen shield; 400 is where Notification Center
/// sits *at* the lock screen, which is why a window there composites above it.
enum SpaceLevel: Int32 {
    case screenLock = 300
    case notificationCenterAtScreenLock = 400
}

final class SkyLightBridge {
    static let shared = SkyLightBridge()

    private typealias FnMainConnectionID = @convention(c) () -> Int32
    private typealias FnSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias FnSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias FnShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias FnSpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let mainConnectionID: FnMainConnectionID
    private let spaceCreate: FnSpaceCreate
    private let spaceSetAbsoluteLevel: FnSpaceSetAbsoluteLevel
    private let showSpaces: FnShowSpaces
    private let spaceAddWindows: FnSpaceAddWindows

    let connection: Int32
    let space: Int32

    /// Non-nil only if every required symbol resolved. This is the capability probe that will
    /// become the version gate in the real app.
    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else { return nil }

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }

        guard
            let f1 = sym("SLSMainConnectionID", as: FnMainConnectionID.self),
            let f2 = sym("SLSSpaceCreate", as: FnSpaceCreate.self),
            let f3 = sym("SLSSpaceSetAbsoluteLevel", as: FnSpaceSetAbsoluteLevel.self),
            let f4 = sym("SLSShowSpaces", as: FnShowSpaces.self),
            let f5 = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", as: FnSpaceAddWindows.self)
        else { return nil }

        mainConnectionID = f1
        spaceCreate = f2
        spaceSetAbsoluteLevel = f3
        showSpaces = f4
        spaceAddWindows = f5

        connection = mainConnectionID()
        space = spaceCreate(connection, 1, 0)
        let levelErr = spaceSetAbsoluteLevel(
            connection, space, SpaceLevel.notificationCenterAtScreenLock.rawValue
        )
        let showErr = showSpaces(connection, [space] as CFArray)
        log("SkyLight: connection=\(connection) space=\(space) setLevel=\(levelErr) showSpaces=\(showErr)")
    }

    static let probe: SkyLightBridge? = SkyLightBridge()

    func adopt(_ window: NSWindow) {
        let err = spaceAddWindows(connection, space, [window.windowNumber] as CFArray, 7)
        log("SkyLight: adopted window #\(window.windowNumber) -> err=\(err)")
    }
}

// MARK: - The lock screen panel
//
// SAFETY: this is a NON-ACTIVATING panel that can never become key or main.
// Mouse clicks route to it; keyboard events never do. Password capture is therefore
// structurally impossible, not merely unimplemented.

final class LockScreenPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        // Public AppKit API, macOS 10.5+: permits the window onscreen before the user logs in.
        canBecomeVisibleWithoutLogin = true

        level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: true)
    }

    // These two overrides are the safety guarantee.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Spike content view

final class SpikeView: NSView {
    private let clockLabel = NSTextField(labelWithString: "")
    private var clickCount = 0
    private let countLabel = NSTextField(labelWithString: "clicks while locked: 0")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 24
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let title = NSTextField(labelWithString: "Nocta Lock Screen Spike")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .white

        clockLabel.font = .monospacedDigitSystemFont(ofSize: 40, weight: .light)
        clockLabel.textColor = .white

        countLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        countLabel.textColor = .systemGreen

        let button = NSButton(title: "  Click me  ", target: self, action: #selector(clicked))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 18, weight: .semibold)

        let stack = NSStackView(views: [title, clockLabel, button, countLabel])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // Bottom-anchored, well clear of the centred avatar / password / Touch ID region.
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -80),
            card.widthAnchor.constraint(equalToConstant: 420),
            card.heightAnchor.constraint(equalToConstant: 280),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            self?.clockLabel.stringValue = f.string(from: Date())
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() {
        clickCount += 1
        let locked = screenIsLocked()
        log(">>> BUTTON CLICKED (#\(clickCount)) — this click \(locked ? "HAPPENED WHILE LOCKED ✅" : "happened while unlocked")")
        countLabel.stringValue = "clicks: \(clickCount)  (last: \(locked ? "LOCKED ✅" : "unlocked"))"
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controllers: [NSWindowController] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        log("=== SPIKE START — macOS \(ProcessInfo.processInfo.operatingSystemVersionString) ===")

        guard let sky = SkyLightBridge.probe else {
            log("RESULT Q1: FAILED — SkyLight symbols did not resolve. Lock screen unsupported here.")
            return
        }

        for (i, screen) in NSScreen.screens.enumerated() {
            let panel = LockScreenPanel(screen: screen)
            panel.contentView = SpikeView(frame: screen.frame)
            sky.adopt(panel)
            panel.orderFrontRegardless()
            controllers.append(NSWindowController(window: panel))
            log("panel \(i) placed on screen \(i) frame=\(screen.frame) canBecomeKey=\(panel.canBecomeKey)")
        }

        log("SAFETY: canBecomeKey=false on all panels — keyboard events can never reach us.")

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            log("EVENT: screenIsLocked")
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            log("EVENT: screenIsUnlocked")
        }

        log("Ready. Lock the screen (Ctrl-Cmd-Q) and try clicking the button.")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
