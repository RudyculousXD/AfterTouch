import Foundation
import os

/// Fetches timed lyrics from [LRCLIB](https://lrclib.net), a free, open, key-less lyrics
/// database.
///
/// This is the only third party Nocta ever contacts, and it is off unless the user turns it on
/// in Settings. The request carries the playing track's title, artist, album and duration and
/// nothing else — no account identifier, no listening history.
///
/// LRCLIB is community-contributed and does not license the underlying compositions. That is a
/// deliberate, disclosed choice recorded in the README, not an oversight.
struct LrclibClient {
    enum LyricsError: LocalizedError {
        case notFound
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notFound:      return "No lyrics found for this track."
            case .http(let code): return "Lyrics service error \(code)."
            }
        }
    }

    private static let log = Logger(subsystem: "app.nocta.Nocta", category: "lyrics")
    private static let base = "https://lrclib.net/api"

    /// LRCLIB asks callers to identify themselves rather than arrive anonymously.
    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return "Nocta/\(version as? String ?? "1.0") (macOS; app.nocta.Nocta)"
    }()

    /// What a lookup produced: timed lines when available, plain text otherwise.
    struct Result: Equatable {
        let synced: SyncedLyrics?
        let plain: String?
        let isInstrumental: Bool

        var isEmpty: Bool { synced == nil && (plain?.isEmpty ?? true) && !isInstrumental }
    }

    private struct Payload: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    /// Exact lookup first — it matches on duration too, so it won't return a different
    /// recording of the same title. Falls back to a search when the exact record is missing.
    func lyrics(for track: Track) async throws -> Result {
        if let payload = try await exact(track) { return Self.result(from: payload) }
        if let payload = try await searched(track) { return Self.result(from: payload) }
        throw LyricsError.notFound
    }

    private func exact(_ track: Track) async throws -> Payload? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        return try await get(path: "/get", query: items, decoding: Payload.self)
    }

    /// The search endpoint returns candidates; the first is LRCLIB's best match.
    private func searched(_ track: Track) async throws -> Payload? {
        let items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        return try await get(path: "/search", query: items, decoding: [Payload].self)?.first
    }

    private func get<T: Decodable>(
        path: String, query: [URLQueryItem], decoding: T.Type
    ) async throws -> T? {
        var components = URLComponents(string: Self.base + path)!
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LyricsError.http(0) }

        switch http.statusCode {
        case 200..<300:
            Self.log.info("GET \(path, privacy: .public) -> \(http.statusCode)")
            return try? JSONDecoder().decode(T.self, from: data)
        case 404:
            // Routine: plenty of tracks simply aren't in the database.
            Self.log.info("GET \(path, privacy: .public) -> 404 (no entry)")
            return nil
        default:
            Self.log.error("GET \(path, privacy: .public) -> \(http.statusCode)")
            throw LyricsError.http(http.statusCode)
        }
    }

    private static func result(from payload: Payload) -> Result {
        Result(
            synced: payload.syncedLyrics.flatMap(SyncedLyrics.init(lrc:)),
            plain: payload.plainLyrics,
            isInstrumental: payload.instrumental ?? false
        )
    }
}
