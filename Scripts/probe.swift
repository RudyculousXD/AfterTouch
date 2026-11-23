// Development probe: dumps one live snapshot from each running provider.
// Confirms selector names resolve and answers the Spotify seconds-vs-milliseconds question
// against the actually-installed build rather than the documentation.
import Foundation

func dump(_ provider: MediaProvider) async {
    print("── \(provider.displayName) ──────────────────────────────")
    guard provider.isRunning() else { print("  not running\n"); return }
    do {
        let s = try await provider.snapshot()
        print("  status      : \(s.status)")
        print("  position    : \(String(format: "%.2f", s.position))s")
        print("  volume      : \(s.volume)   muted=\(s.isMuted)")
        print("  shuffle     : \(s.isShuffling)   repeat=\(s.repeatMode)")
        if let t = s.track {
            print("  title       : \(t.title)")
            print("  artist      : \(t.artist)")
            print("  album       : \(t.album)")
            print("  duration    : \(String(format: "%.2f", t.duration))s  (\(Int(t.duration)/60)m\(Int(t.duration)%60)s)")
            print("  id          : \(t.id)")
            print("  favourite   : \(String(describing: t.isFavorite))")
            switch t.artwork {
            case .url(let u):    print("  artwork     : URL \(u.absoluteString)")
            case .data(let d):   print("  artwork     : \(d.count) bytes of image data")
            case nil:            print("  artwork     : none")
            }
            let ratio = s.position / max(t.duration, 0.001)
            print("  sanity      : position/duration = \(String(format: "%.3f", ratio)) (must be 0...1)")
        } else {
            print("  (no current track)")
        }
    } catch {
        print("  ERROR: \(error.localizedDescription)")
    }
    print("")
}

@main
struct Probe {
    static func main() async {
        let spotify = SpotifyProvider()
        let music = AppleMusicProvider()

        // Raw, un-normalised Spotify duration, to see what the app really returns.
        if spotify.isRunning() {
            let raw = (try? await spotify.snapshot())?.track?.duration
            print("Spotify normalised duration => \(String(describing: raw))")
            print("  (normalisedDuration treats any value > 10000 as milliseconds)\n")
        }

        await dump(spotify)
        await dump(music)
    }
}
