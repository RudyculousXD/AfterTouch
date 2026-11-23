import AppKit
import Foundation

/// PRIVATE API BOUNDARY.
///
/// This file and `SkyLightLockScreenPresenter` are the *only* places in Nocta that touch
/// private macOS APIs. Nothing else imports or references SkyLight, so if Apple changes or
/// removes these symbols the damage is contained to two files and degrades to
/// `UnsupportedLockScreenPresenter`.
///
/// ## What this does
/// SkyLight is the private C layer WindowServer uses to drive every window on screen. We
/// create a *space*, raise that space's absolute level above the lock screen shield, show it,
/// and move our panel into it. A window in that space composites above the lock screen.
///
/// ## Attribution
/// The call sequence was learned from SkyLightWindow by Lakr233 (MIT licensed), and the
/// function signatures are factual C declarations. No GPL-licensed code (e.g. Atoll) was
/// copied into this project. See NOTICE.
///
/// ## Verified
/// 2026-08-20, macOS 26.6.2 (build 25G83): all five symbols resolved, every call returned
/// `kCGErrorSuccess`, and the resulting panel accepted mouse clicks while the Mac was locked.
final class SkyLightBridge {

    /// Absolute space levels. Values below 300 sit under the lock screen; the level we want is
    /// the one Notification Center uses *at* the lock screen, which is why it composites above
    /// the shield while still being a place the system expects interactive UI to live.
    enum SpaceLevel: Int32 {
        case `default` = 0
        case setupAssistant = 100
        case securityAgent = 200
        case screenLock = 300
        case notificationCenterAtScreenLock = 400
        case bootProgress = 500
        case voiceOver = 600
    }

    private typealias FnMainConnectionID = @convention(c) () -> Int32
    private typealias FnSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias FnSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    // SLSShowSpaces is a void function. Treating its undefined return register as a status
    // code happened to work on some macOS releases, but can produce arbitrary nonzero values.
    private typealias FnShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias FnSpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let spaceCreate: FnSpaceCreate
    private let spaceSetAbsoluteLevel: FnSpaceSetAbsoluteLevel
    private let showSpaces: FnShowSpaces
    private let spaceAddWindows: FnSpaceAddWindows

    private let connection: Int32
    private let space: Int32

    /// Magic constant from the SkyLight ABI: the "selector" for moving windows between spaces.
    private static let addWindowsSelector: Int32 = 7

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// The capability probe and the version gate in one. Returns `nil` if the framework can't
    /// be loaded, any symbol is missing, or the space can't be created — which is exactly what
    /// we expect to happen on some future macOS. Callers fall back rather than crash.
    init?() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else { return nil }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        guard
            let mainConnectionID = symbol("SLSMainConnectionID", as: FnMainConnectionID.self),
            let create = symbol("SLSSpaceCreate", as: FnSpaceCreate.self),
            let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: FnSpaceSetAbsoluteLevel.self),
            let show = symbol("SLSShowSpaces", as: FnShowSpaces.self),
            let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: FnSpaceAddWindows.self)
        else { return nil }

        spaceCreate = create
        spaceSetAbsoluteLevel = setLevel
        showSpaces = show
        spaceAddWindows = addWindows

        connection = mainConnectionID()
        guard connection != 0 else { return nil }

        space = spaceCreate(connection, 1, 0)
        guard space != 0 else { return nil }

        let levelResult = spaceSetAbsoluteLevel(
            connection, space, SpaceLevel.notificationCenterAtScreenLock.rawValue
        )
        guard levelResult == 0 else { return nil }
        showSpace()
    }

    /// Puts our space back into the window server's set of shown spaces.
    ///
    /// This is not redundant with the call in `init`, and getting that wrong is what made the
    /// card vanish after the displays slept: when the displays wake while the Mac is locked,
    /// the window server rebuilds the lock screen's shown-space set, and ours is not in the set
    /// it rebuilds from. Afterwards the panel is still *in* our space and our space is no
    /// longer *shown*, so re-adopting the window alone puts it nowhere visible. Re-showing is
    /// what brings it back. Idempotent and cheap.
    func showSpace() {
        showSpaces(connection, [space] as CFArray)
    }

    /// Moves a window into the lock-screen-level space. Safe to call repeatedly.
    @discardableResult
    func adopt(_ window: NSWindow) -> Bool {
        guard window.windowNumber != 0 else { return false }
        let result = spaceAddWindows(
            connection, space, [window.windowNumber] as CFArray, Self.addWindowsSelector
        )
        return result == 0
    }

    /// Whether the technique is available at all, without constructing anything. Used by the
    /// UI to explain the unsupported state before the user goes looking for a missing feature.
    static var isAvailable: Bool {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return false }
        let required = [
            "SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel",
            "SLSShowSpaces", "SLSSpaceAddWindowsAndRemoveFromSpaces",
        ]
        return required.allSatisfy { dlsym(handle, $0) != nil }
    }
}
