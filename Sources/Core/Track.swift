import Foundation

/// Where a track's artwork can be obtained from.
///
/// The two cases exist because the two providers genuinely differ: Spotify's scripting
/// dictionary marks its `artwork` (image data) property deprecated — *"will never be set.
/// Use the 'artwork url' instead"* — while Music.app exposes raw picture `data` through the
/// `artworks` element of the current track.
enum ArtworkSource: Equatable, Hashable {
    case url(URL)
    case data(Data)
}

/// A single piece of playing media, normalised across providers.
struct Track: Equatable, Identifiable {
    /// Provider-scoped identifier. Used to detect track changes without comparing every field.
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artwork: ArtworkSource?

    /// `nil` means "this provider cannot tell us", which is different from "not a favourite".
    /// Spotify's AppleScript `starred` is read-only, so writing it requires the Web API.
    var isFavorite: Bool?

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artwork: ArtworkSource? = nil,
        isFavorite: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artwork = artwork
        self.isFavorite = isFavorite
    }
}

extension Track {
    /// Identity for animation purposes: artwork bytes are deliberately excluded so that
    /// artwork arriving late does not read as a track change.
    var changeKey: String { "\(id)|\(title)|\(artist)|\(album)" }
}
