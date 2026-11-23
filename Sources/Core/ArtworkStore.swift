import AppKit
import Observation
import SwiftUI

/// Resolves `ArtworkSource` values into images and derives an accent colour from them.
///
/// Kept separate from `MediaController` because artwork arrives asynchronously (Spotify hands
/// us a CDN URL, not bytes) and must never make the rest of the state wait. Results are
/// cached by track id so flipping back and forth between tracks doesn't refetch.
@MainActor
@Observable
final class ArtworkStore {
    private(set) var image: NSImage?
    /// Derived from the artwork, used to tint the player. Falls back to a neutral accent.
    private(set) var accent: Color = Color(nsColor: .controlAccentColor)

    @ObservationIgnored private var cache: [String: NSImage] = [:]
    @ObservationIgnored private var accentCache: [String: Color] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private let cacheLimit = 24

    /// Call whenever the current track changes. A `nil` track clears the artwork.
    func update(for track: Track?) {
        guard let track else {
            inFlight?.cancel()
            currentKey = nil
            image = nil
            accent = Color(nsColor: .controlAccentColor)
            return
        }

        let key = track.id
        guard key != currentKey else { return }
        currentKey = key

        if let cached = cache[key] {
            touch(key)
            image = cached
            accent = accentCache[key] ?? Color(nsColor: .controlAccentColor)
            return
        }

        inFlight?.cancel()
        guard let source = track.artwork else {
            image = nil
            accent = Color(nsColor: .controlAccentColor)
            return
        }

        inFlight = Task { [weak self] in
            let loaded = await Self.resolve(source)
            guard let self, !Task.isCancelled, self.currentKey == key else { return }
            guard let loaded else {
                self.image = nil
                return
            }
            let derived = Self.accentColor(from: loaded)
            self.store(loaded, accent: derived, for: key)
            self.image = loaded
            self.accent = derived
        }
    }

    private func store(_ image: NSImage, accent: Color, for key: String) {
        cache[key] = image
        accentCache[key] = accent
        touch(key)

        // Retain recently played art while evicting one old entry at a time. Clearing the
        // whole cache at the limit made a long listening session refetch every prior cover.
        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
            accentCache.removeValue(forKey: evicted)
        }
    }

    private func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private static func resolve(_ source: ArtworkSource) async -> NSImage? {
        switch source {
        case .data(let data):
            return NSImage(data: data)
        case .url(let url):
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard
                let (data, response) = try? await URLSession.shared.data(for: request),
                let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return nil }
            return NSImage(data: data)
        }
    }

    /// Average the artwork down to a single pixel, then push saturation and brightness into a
    /// range that stays legible against both light and dark backgrounds.
    static func accentColor(from image: NSImage) -> Color {
        guard
            let tiff = image.tiffRepresentation,
            let source = NSBitmapImageRep(data: tiff),
            let cgImage = source.cgImage
        else { return Color(nsColor: .controlAccentColor) }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Color(nsColor: .controlAccentColor) }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let base = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        guard let hsb = base.usingColorSpace(.sRGB) else {
            return Color(nsColor: .controlAccentColor)
        }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        hsb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // A washed-out average reads as grey; a very dark one disappears. Clamp both.
        let tuned = NSColor(
            hue: hue,
            saturation: min(max(saturation * 1.5, 0.45), 0.9),
            brightness: min(max(brightness * 1.25, 0.6), 0.95),
            alpha: 1
        )
        return Color(nsColor: tuned)
    }
}
