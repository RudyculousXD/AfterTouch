import Foundation
import os

/// Thin Spotify Web API client covering only what Apple Events cannot do.
///
/// Playback control deliberately does **not** go through here: the Web API's control endpoints
/// require Premium, add network latency, and target whichever Spotify Connect device is active
/// — which may not be this Mac. Apple Events are strictly better for that. This client exists
/// solely for the library ("like") endpoints, which have no Apple Events equivalent because
/// Spotify's `starred` property is broken in shipping builds.
///
/// Uses the unified `/me/library` endpoints. The older `/me/tracks` family is deprecated and —
/// verified 2026-08-21 against a token with `user-library-read user-library-modify` on an
/// allowlisted account — answers `403 Forbidden` with an empty body, which is indistinguishable
/// from a permissions failure. That dead end cost an evening; it is recorded here so it does
/// not cost another one.
struct SpotifyWebClient {
    let auth: SpotifyAuth

    /// Failures here are swallowed by callers so that a Web API problem can never break
    /// playback, which makes the log the only place a `403` or a `429` is visible. Read with:
    ///   log show --last 10m --predicate 'subsystem == "app.nocta.Nocta"'
    private static let log = Logger(subsystem: "app.nocta.Nocta", category: "spotify-web")

    enum WebError: LocalizedError {
        case notConnected
        case rateLimited(retryAfter: Int)
        /// Spotify answers a blanket `403 Forbidden`, with no explanation in the body, when
        /// the *application* is not permitted to call the Web API for this user. Sign-in
        /// still succeeds, so it surfaces only on the first real request. The two causes are
        /// both settings in the user's own dashboard app, so the message names them rather
        /// than echoing Spotify's empty one.
        case forbidden
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Connect your Spotify account in Settings to use favourites."
            case .rateLimited(let seconds):
                return "Spotify is rate limiting requests. Try again in \(seconds)s."
            case .forbidden:
                return "Spotify denied access (403). Disconnect and connect again to regrant "
                    + "permissions. If that doesn't help, check your app at "
                    + "developer.spotify.com: Web API enabled, and your account listed under "
                    + "User Management."
            case .http(let code, let detail):
                return "Spotify API error \(code): \(detail)"
            }
        }
    }

    /// Spotify track URIs look like `spotify:track:5WTj1jVzufTuSzFMyjy60M`. The library
    /// endpoints take the whole URI, so this only validates the shape — it returns nil for
    /// anything that isn't a track, such as a local file or a podcast episode.
    static func trackURI(validating uri: String) -> String? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[1] == "track" else { return nil }
        return uri
    }

    func isSaved(trackURI: String) async throws -> Bool {
        guard let uri = Self.trackURI(validating: trackURI) else { return false }
        let data = try await send("GET", path: "/me/library/contains", uris: [uri])
        return (try? JSONDecoder().decode([Bool].self, from: data))?.first ?? false
    }

    func setSaved(_ saved: Bool, trackURI: String) async throws {
        guard let uri = Self.trackURI(validating: trackURI) else { return }
        _ = try await send(saved ? "PUT" : "DELETE", path: "/me/library", uris: [uri])
    }

    // MARK: - Repeat

    /// The player's repeat state, or `nil` when Spotify reports no active playback session
    /// (`204 No Content`). Apple Events cannot answer this: `repeating` is a boolean there, so
    /// "all" and "one" are indistinguishable in both directions.
    func repeatState() async throws -> RepeatMode? {
        let data = try await send("GET", path: "/me/player", encodedQuery: nil)
        guard !data.isEmpty else { return nil }

        struct PlayerState: Decodable { let repeat_state: String? }
        guard let state = (try? JSONDecoder().decode(PlayerState.self, from: data))?.repeat_state
        else { return nil }
        return Self.repeatMode(fromAPI: state)
    }

    func setRepeat(_ mode: RepeatMode) async throws {
        _ = try await send(
            "PUT", path: "/me/player/repeat", encodedQuery: "state=" + Self.apiValue(for: mode)
        )
    }

    /// Spotify names the three states off/context/track; `context` is "repeat the album or
    /// playlist", which is what the rest of the app calls `.all`.
    static func apiValue(for mode: RepeatMode) -> String {
        switch mode {
        case .off: return "off"
        case .all: return "context"
        case .one: return "track"
        }
    }

    static func repeatMode(fromAPI value: String) -> RepeatMode? {
        switch value {
        case "off":     return .off
        case "context": return .all
        case "track":   return .one
        default:        return nil
        }
    }

    // MARK: - Requests

    /// `uris` carries Spotify URIs, whose colons must be percent-encoded while the separating
    /// commas must not be. `URLComponents.queryItems` leaves the colons literal, which is legal
    /// but not the form Spotify documents, so the query is built by hand.
    private func send(_ method: String, path: String, uris: [String]) async throws -> Data {
        try await send(
            method, path: path,
            encodedQuery: "uris=" + uris.map(Self.encodeURI).joined(separator: ",")
        )
    }

    private func send(
        _ method: String, path: String, encodedQuery: String?
    ) async throws -> Data {
        guard let token = await auth.validAccessToken() else { throw WebError.notConnected }

        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        components.percentEncodedQuery = encodedQuery

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebError.http(0, "no response")
        }

        switch http.statusCode {
        case 200..<300:
            // .info, not .debug: debug messages are memory-only and routinely dropped, which
            // makes "did this request even happen?" unanswerable after the fact. At most one
            // request per track per minute, so this stays quiet.
            Self.log.info("\(method, privacy: .public) \(path, privacy: .public) -> \(http.statusCode)")
            return data
        case 429:
            let retry = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
            Self.log.error(
                "\(method, privacy: .public) \(path, privacy: .public) -> 429, retry after \(retry)s"
            )
            throw WebError.rateLimited(retryAfter: retry)
        case 403:
            Self.log.error(
                """
                \(method, privacy: .public) \(path, privacy: .public) -> 403. The token is \
                valid, so this is an app-level refusal: check that Web API is enabled for the \
                app at developer.spotify.com, and that this Spotify account is listed under \
                User Management while the app is in Development mode.
                """
            )
            await diagnoseForbidden(token: token)
            throw WebError.forbidden
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.log.error(
                "\(method, privacy: .public) \(path, privacy: .public) -> \(http.statusCode): \(body, privacy: .public)"
            )
            throw WebError.http(http.statusCode, body)
        }
    }

    private static func encodeURI(_ uri: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return uri.addingPercentEncoding(withAllowedCharacters: allowed) ?? uri
    }

    // MARK: - 403 diagnosis

    /// Runs once per launch, the first time a request is refused with `403`.
    ///
    /// `/me` requires no scope at all, so its answer separates the two causes that are
    /// otherwise indistinguishable — Spotify's 403 body is empty in both cases:
    ///
    /// - `/me` also 403: the *application* may not act for this account. The account is not
    ///   listed in the dashboard app's User Management, or it is not the account that was
    ///   authorised in the first place.
    /// - `/me` 200: the account is fine and the token works. The refusal is then specific to
    ///   the saved-tracks endpoints, i.e. the grant is missing `user-library-read` /
    ///   `user-library-modify` and the user must reconnect.
    ///
    /// Identity is logged as display name and Spotify user id, never the email address.
    private func diagnoseForbidden(token: String) async {
        guard Self.diagnosisPending.takeIfPending() else { return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        struct Profile: Decodable {
            let display_name: String?
            let id: String
            let product: String?
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            Self.log.error("403 diagnosis: /me could not be reached")
            return
        }

        guard http.statusCode == 200, let profile = try? JSONDecoder().decode(Profile.self, from: data) else {
            Self.log.error(
                """
                403 diagnosis: /me -> \(http.statusCode). The app is refused for this account \
                entirely, so the account that was authorised is not the one listed under User \
                Management. Reconnect and sign in as the listed account.
                """
            )
            return
        }

        Self.log.error(
            """
            403 diagnosis: /me -> 200 as "\(profile.display_name ?? "unknown", privacy: .public)" \
            (id \(profile.id, privacy: .public), \(profile.product ?? "unknown plan", privacy: .public)). \
            This account works, so the refusal is scope-specific: reconnect to regrant \
            user-library-read and user-library-modify.
            """
        )
    }

    /// Keeps the diagnosis to one probe per launch; the 403 recurs on every poll.
    private static let diagnosisPending = PendingOnce()
}

final class PendingOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = true

    /// True exactly once, for the first caller.
    func takeIfPending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pending else { return false }
        pending = false
        return true
    }
}
