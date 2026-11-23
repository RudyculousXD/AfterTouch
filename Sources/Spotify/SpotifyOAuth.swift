import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import os

/// Tokens as persisted in the Keychain. Never written anywhere else.
struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// Refresh slightly early so a request never races the expiry boundary.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

enum SpotifyAuthError: LocalizedError {
    case missingClientID
    case cancelled
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Add your Spotify client ID in Settings before connecting."
        case .cancelled:
            return "Sign-in was cancelled."
        case .badResponse(let detail):
            return "Spotify rejected the sign-in: \(detail)"
        }
    }
}

/// Spotify OAuth using **Authorization Code with PKCE**.
///
/// PKCE is the correct flow for a desktop app: there is no client secret to embed, which is
/// why none is stored anywhere in this project. The user registers their own Spotify app and
/// pastes its client ID, so no shared credential ships with Nocta.
///
/// This layer is entirely optional. Playback control works over Apple Events without it; the
/// only thing signing in unlocks is Spotify's "like"/save, which cannot be done over Apple
/// Events at all (see `SpotifyProvider`).
@MainActor
@Observable
final class SpotifyAuth: NSObject {
    private static let tokenAccount = "oauth-tokens"
    private static let clientIDKey = "spotifyClientID"
    private static let redirectURI = "nocta://spotify-callback"
    private static let callbackScheme = "nocta"
    /// Library scopes drive the heart; player scopes exist only for repeat-one, which Apple
    /// Events cannot express. Adding a scope invalidates an existing grant's usefulness — a
    /// token issued before this line changed will 403 on the player endpoints until the user
    /// reconnects, which `SpotifyProvider` degrades around rather than failing on.
    private static let scopes = "user-library-read user-library-modify "
        + "user-read-playback-state user-modify-playback-state"

    private(set) var isConnected: Bool = false {
        didSet { connectionFlag.value = isConnected }
    }
    private(set) var lastError: String?

    /// Providers run off the main actor (Apple Events must never block the main thread), so
    /// they need a synchronous, thread-safe way to ask whether we're signed in. This mirrors
    /// `isConnected` behind a lock rather than forcing every caller to hop actors.
    private let connectionFlag = LockedFlag()
    nonisolated var isConnectedNonisolated: Bool { connectionFlag.value }

    /// The user's own Spotify application client ID. Not a secret — a client ID is public by
    /// design under PKCE — so `UserDefaults` is the right home for it, not the Keychain.
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Self.clientIDKey) }
    }

    @ObservationIgnored private var tokens: SpotifyTokens? {
        didSet { isConnected = tokens != nil }
    }
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private var verifier: String?

    override init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        super.init()
        do {
            tokens = try KeychainStore.load(SpotifyTokens.self, account: Self.tokenAccount)
        } catch {
            // Denying the prompt, or a signature the item's ACL no longer recognises, used to
            // read as "never signed in": the heart simply disappeared, because `.favorite` is
            // withdrawn when not connected. Say what happened instead.
            tokens = nil
            lastError = "Could not read the Spotify sign-in from your Keychain. "
                + "Reopen Nocta and allow the Keychain prompt, or Connect again."
            Self.log.error("keychain read refused: \(error.localizedDescription, privacy: .public)")
        }
        isConnected = tokens != nil
        connectionFlag.value = isConnected
    }

    // MARK: - Sign in / out

    func connect() async {
        lastError = nil
        guard !clientID.isEmpty else {
            lastError = SpotifyAuthError.missingClientID.localizedDescription
            return
        }

        let verifier = Self.makeCodeVerifier()
        self.verifier = verifier

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: Self.makeCodeChallenge(from: verifier)),
            .init(name: "scope", value: Self.scopes),
        ]

        do {
            let callback = try await authorize(url: components.url!)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            else { throw SpotifyAuthError.badResponse("no authorization code returned") }

            let fresh = try await exchange(code: code, verifier: verifier)
            try KeychainStore.save(fresh, account: Self.tokenAccount)
            tokens = fresh
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        try? KeychainStore.delete(account: Self.tokenAccount)
        tokens = nil
        lastError = nil
    }

    private func authorize(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyAuthError.cancelled)
                } else {
                    continuation.resume(
                        throwing: error ?? SpotifyAuthError.badResponse("unknown failure")
                    )
                }
            }
            session.presentationContextProvider = self
            // Use an isolated session rather than Safari's shared cookies. With the shared
            // session, whichever Spotify account Safari happens to be signed into is
            // authorised silently, with no account shown and no way to choose another — and
            // authorising the wrong account fails later as an unexplained 403, because only
            // the accounts listed in the dashboard app's User Management may call the API.
            // Ephemeral costs one password entry on connect and makes the account explicit.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    // MARK: - Tokens

    /// A valid access token, refreshing transparently if needed. `nil` when not connected.
    func validAccessToken() async -> String? {
        guard let current = tokens else { return nil }
        guard current.isExpired else { return current.accessToken }

        do {
            let refreshed = try await refresh(using: current.refreshToken)
            try KeychainStore.save(refreshed, account: Self.tokenAccount)
            tokens = refreshed
            return refreshed.accessToken
        } catch {
            // A failed refresh usually means the grant was revoked; make the user reconnect
            // rather than silently retrying forever.
            lastError = "Spotify sign-in expired. Connect again."
            disconnect()
            return nil
        }
    }

    private static let log = Logger(subsystem: "app.nocta.Nocta", category: "spotify-auth")

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        /// What Spotify actually granted, which is not always what was asked for. Logged so a
        /// missing `user-library-*` scope is distinguishable from an app-level 403.
        let scope: String?
    }

    private func exchange(code: String, verifier: String) async throws -> SpotifyTokens {
        try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], existingRefreshToken: nil)
    }

    private func refresh(using refreshToken: String) async throws -> SpotifyTokens {
        try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], existingRefreshToken: refreshToken)
    }

    private func postToken(
        _ fields: [String: String], existingRefreshToken: String?
    ) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no detail"
            throw SpotifyAuthError.badResponse(body)
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        Self.log.info("token granted, scopes: \(decoded.scope ?? "none returned", privacy: .public)")
        // Spotify omits refresh_token on some refresh responses; keep the one we have.
        guard let refresh = decoded.refresh_token ?? existingRefreshToken else {
            throw SpotifyAuthError.badResponse("no refresh token returned")
        }
        return SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func makeCodeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        }
    }
}


/// Minimal thread-safe boolean. Exists so `SpotifyAuth` can publish its connection state to
/// non-main-actor callers without an `await`.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
