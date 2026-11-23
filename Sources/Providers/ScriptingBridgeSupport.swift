import AppKit
import Foundation
import ScriptingBridge

/// Builds an OSType from a four-character code, e.g. `fourCharCode("kPSP")`.
/// The scripting enums are defined this way in the generated headers.
func fourCharCode(_ string: StaticString) -> UInt32 {
    let bytes = Array(String(describing: string).utf8)
    precondition(bytes.count == 4, "four-char code must be exactly 4 bytes")
    return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

enum PlayerStateCode {
    static let stopped = fourCharCode("kPSS")
    static let playing = fourCharCode("kPSP")
    static let paused  = fourCharCode("kPSp")

    static func status(from raw: UInt32) -> PlaybackStatus {
        switch raw {
        case playing: return .playing
        case paused:  return .paused
        default:      return .stopped   // includes fast-forwarding / rewinding on Music.app
        }
    }
}

/// Records Apple Event failures, which `SBApplication` otherwise swallows silently.
private final class ErrorRecordingDelegate: NSObject, SBApplicationDelegate {
    var lastError: NSError?

    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        lastError = error as NSError
        return nil
    }
}

/// Serialises all Apple Event traffic onto a background queue.
///
/// Apple Events are synchronous and can block for seconds if the target app is busy, so they
/// must never run on the main thread. A bounded `timeout` means a wedged music app degrades
/// to a stale reading instead of beach-balling the whole app.
final class ScriptingBridgeClient {
    private let queue: DispatchQueue
    private let bundleIdentifier: String
    private let appName: String
    private let delegate = ErrorRecordingDelegate()

    /// Apple Event timeout expressed in ticks (1/60 s). 120 ticks == 2 seconds.
    private static let timeoutTicks: Int = 120

    init(bundleIdentifier: String, appName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.queue = DispatchQueue(
            label: "app.nocta.applescript.\(bundleIdentifier)",
            qos: .userInitiated
        )
    }

    /// True when the app is already running. We check this before every access so that
    /// merely observing state never launches Spotify or Music.
    func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Runs `body` against the scripting object on the serial queue.
    ///
    /// `body` receives the raw `SBApplication`; callers reinterpret it as their `@objc`
    /// protocol. Returns `.notRunning` rather than launching the app.
    func run<T>(_ body: @escaping (SBApplication) throws -> T) async throws -> T {
        guard isRunning() else { throw ProviderError.notRunning(appName: appName) }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let app = SBApplication(bundleIdentifier: bundleIdentifier) else {
                    continuation.resume(throwing: ProviderError.notRunning(appName: appName))
                    return
                }
                app.timeout = Self.timeoutTicks
                app.delegate = delegate
                delegate.lastError = nil

                do {
                    let value = try body(app)
                    if let error = delegate.lastError {
                        continuation.resume(throwing: mapped(error))
                    } else {
                        continuation.resume(returning: value)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func mapped(_ error: NSError) -> ProviderError {
        switch error.code {
        case -1743:                    // errAEEventNotPermitted
            return .automationDenied(appName: appName)
        case -600, -609:               // procNotFound / connectionInvalid
            return .notRunning(appName: appName)
        case -1712:                    // errAETimeout
            return .timedOut
        default:
            return .failed("\(appName): \(error.localizedDescription)")
        }
    }
}
