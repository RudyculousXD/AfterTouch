import AppKit
import Foundation
import SwiftUI

/// Decides how large the Lock Screen controller is and where it is allowed to sit.
///
/// This exists because of a real defect found during the Stage 1 spike: a card anchored 80pt
/// from the bottom of the screen landed directly on top of the user avatar and pushed the
/// "Touch ID or Enter Password" prompt underneath it. Overlapping the unlock UI is the one
/// thing this app must never do, so placement is constrained rather than left to chance.
///
/// The reserved bands below were measured from a macOS 26.6 lock screen at 1512×982:
///   • the clock and date occupy roughly the top 9%–24%
///   • the avatar, name and password prompt begin near the bottom 15%
/// They are expressed as fractions so they scale with display size, and are padded outward
/// from the measured values to leave margin for longer names and localised prompts.
///
/// ## Collapsed and expanded
/// **Collapsed** is one wide card with the artwork inset inside it. **Expanded** lifts the
/// artwork out of the card — bare, with no surface of its own — and leaves the player beneath
/// it at the same width, so the bar never changes shape, only height. The panel is sized to
/// the union of the two footprints, so nothing has to be resized mid-animation. The collapsed
/// card is aligned to whichever edge of that footprint matches the user's chosen position, so
/// expansion grows *away* from the unlock UI. `LockScreenPanel` only accepts clicks inside the
/// current arrangement's rect, so the unused part of the panel stays click-through.
enum LockScreenLayout {

    /// Top fraction of the screen reserved for the lock screen clock and date.
    static let clockReserve: CGFloat = 0.26
    /// Bottom fraction reserved for the avatar, user name, password field and Touch ID prompt.
    static let authReserve: CGFloat = 0.15
    /// Minimum breathing room between the card and the edge of a reserved band.
    static let margin: CGFloat = 24

    /// The collapsed card: one surface, artwork inset in its top-leading corner.
    ///
    /// Proportioned after the iOS Now Playing card — a header row, the scrubber across the
    /// full width, then the transport — rather than the single band it used to be. Type is
    /// deliberately *not* scaled with it: 12pt on a 360pt-wide phone card would be 17pt at
    /// this width, which reads as a poster on a Mac. Sizes stay at desktop values and the
    /// extra width becomes air, which is what the reference spends it on anyway.
    static let collapsedSize = CGSize(width: 500, height: 204)
    /// Padding between the collapsed card's edge and its contents, including the artwork.
    static let collapsedPadding: CGFloat = 22
    /// Less than the horizontal inset. The card is a wide bar: the side margins set how the
    /// artwork is inset, while the top and bottom only decide how tall the bar reads, and 22
    /// on all four edges made it read as a block rather than a strip.
    static let collapsedPaddingVertical: CGFloat = 12
    /// Minimum breathing room between the header, scrubber and control rows.
    static let collapsedRowGap: CGFloat = 6
    /// The artwork square in the collapsed card's header row. Fixed rather than derived from
    /// the card height — the header is one of three rows now, not the whole card.
    static let collapsedArtwork: CGFloat = 76

    /// Gap between the detached artwork and the player beneath it.
    static let surfaceGap: CGFloat = 12
    /// The expanded player surface: metadata, scrubber, transport and the secondary row.
    static let expandedPlayerHeight: CGFloat = 132
    /// Expanded lyrics live beside the cover, so they do not add a second row to the player.
    /// Keeping this at zero prevents an unused strip of glass beneath the transport controls.
    static let expandedLyricsAllowance: CGFloat = 0
    /// Clear space between the detached cover and the lyric column. The reference gives the
    /// two elements room to read as separate zones instead of one crowded album card.
    static let expandedLyricsGap: CGFloat = 148
    /// Breathing room at the outside edge of the lyric column.
    static let expandedLyricsTrailingInset: CGFloat = 42

    static func expandedPlayerHeight(withLyrics lyrics: Bool) -> CGFloat {
        expandedPlayerHeight + (lyrics ? expandedLyricsAllowance : 0)
    }

    /// Everything in the expanded column that isn't artwork. Artwork takes whatever is left.
    static func expandedChromeHeight(withLyrics lyrics: Bool) -> CGFloat {
        expandedPlayerHeight(withLyrics: lyrics) + surfaceGap
    }
    /// What the expanded arrangement wants, when the screen has room for it.
    static let idealExpandedHeight: CGFloat = 530
    /// Below this the expanded player is too cramped to be worth offering, so the controller
    /// stays collapsed and the artwork stops being a control.
    static let minimumExpandedHeight: CGFloat = 360
    static let expandedArtworkRange: ClosedRange<CGFloat> = 216...400

    /// Everything the view needs to lay itself out on one particular screen.
    struct Metrics: Equatable {
        /// Footprint of the whole arrangement — both surfaces and the gap between them.
        var collapsedSize: CGSize
        var expandedSize: CGSize
        /// Where the collapsed bar sits inside the panel, and therefore which way the card
        /// grows when it expands.
        var anchor: Anchor
        /// False on screens too short to expand without crowding the unlock UI.
        var allowsExpansion: Bool
        /// Side length of the artwork in the expanded player.
        var expandedArtwork: CGFloat
        /// Height of the expanded player surface, which carries the lyric line when it is on.
        var expandedPlayerHeight: CGFloat

        func cardSize(expanded: Bool) -> CGSize {
            expanded && allowsExpansion ? expandedSize : collapsedSize
        }

        /// The panel holds both arrangements: the collapsed bar is the wider of the two, the
        /// expanded column the taller.
        var panelSize: CGSize {
            CGSize(
                width: max(collapsedSize.width, expandedSize.width),
                height: max(collapsedSize.height, expandedSize.height)
            )
        }

        /// The arrangement's rect inside the panel, in top-left (SwiftUI) coordinates.
        func cardRect(expanded: Bool) -> CGRect {
            let panel = panelSize
            let size = cardSize(expanded: expanded)
            let x = (panel.width - size.width) / 2
            let y: CGFloat
            switch anchor {
            case .top:    y = 0
            case .center: y = (panel.height - size.height) / 2
            case .bottom: y = panel.height - size.height
            }
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }

        enum Anchor: Equatable {
            case top, center, bottom

            var swiftUI: Alignment {
                switch self {
                case .top:    .top
                case .center: .center
                case .bottom: .bottom
                }
            }
        }
    }

    /// The vertical band the controller may occupy, in screen coordinates (origin bottom-left,
    /// as AppKit uses).
    static func safeBand(in screenFrame: CGRect) -> CGRect {
        let reservedTop = screenFrame.height * clockReserve
        let reservedBottom = screenFrame.height * authReserve
        let usableHeight = screenFrame.height - reservedTop - reservedBottom
        return CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY + reservedBottom,
            width: screenFrame.width,
            height: max(0, usableHeight)
        )
    }

    static func metrics(
        for position: LockScreenPosition,
        in screenFrame: CGRect,
        lyricsEnabled: Bool = false
    ) -> Metrics {
        let band = safeBand(in: screenFrame)
        let available = band.height - margin * 2
        let width = min(collapsedSize.width, max(320, band.width - margin * 2))

        let allowsExpansion = available >= minimumExpandedHeight
        let expandedHeight = allowsExpansion
            ? min(idealExpandedHeight, available)
            : collapsedSize.height
        // The expanded state is a centered album view. Lyrics mode uses the same footprint,
        // moving the cover left to make room for a clean lyric column on its right.
        // Lyrics sit in a full-size column beside the cover. A narrow column forced the
        // reference's five lines into ellipses, so give this state enough width to breathe.
        let expandedWidth = min(screenFrame.width - margin * 2, max(width, width + 620))
        let artwork = min(
            expandedArtworkRange.upperBound,
            max(expandedArtworkRange.lowerBound,
                expandedHeight - expandedPlayerHeight(withLyrics: lyricsEnabled) - surfaceGap)
        )

        let anchor: Metrics.Anchor
        switch position {
        // The card grows away from whichever reserved band it sits closest to.
        case .top:         anchor = .top
        case .upperMiddle: anchor = .center
        case .bottom:      anchor = .bottom
        }

        return Metrics(
            collapsedSize: CGSize(width: width, height: collapsedSize.height),
            expandedSize: CGSize(width: expandedWidth, height: expandedHeight),
            anchor: anchor,
            allowsExpansion: allowsExpansion,
            expandedArtwork: artwork,
            expandedPlayerHeight: expandedPlayerHeight(withLyrics: lyricsEnabled)
        )
    }

    /// Final panel frame: horizontally centred, vertically placed per the user's preference,
    /// then clamped so it can never intrude into either reserved band. The panel is sized to
    /// the expanded card, so this frame bounds the card in *both* states.
    static func frame(
        for position: LockScreenPosition,
        in screenFrame: CGRect,
        metrics: Metrics
    ) -> CGRect {
        let size = metrics.panelSize
        let band = safeBand(in: screenFrame)
        let x = screenFrame.midX - size.width / 2

        // If the panel cannot fit in the safe band at all, centre it in the band and accept
        // the overflow rather than pushing it onto the password field.
        guard band.height > size.height + margin * 2 else {
            return CGRect(
                x: x,
                y: band.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        let lowest = band.minY + margin
        let highest = band.maxY - size.height - margin

        let y: CGFloat
        switch position {
        case .top:         y = highest
        case .upperMiddle: y = (lowest + highest) / 2
        case .bottom:      y = lowest
        }

        return CGRect(
            x: x,
            y: min(max(y, lowest), highest),
            width: size.width,
            height: size.height
        )
    }

    /// Convenience for callers that don't need the metrics separately.
    static func frame(for position: LockScreenPosition, in screenFrame: CGRect) -> CGRect {
        frame(for: position, in: screenFrame, metrics: metrics(for: position, in: screenFrame))
    }

    /// True when the proposed frame stays entirely clear of both reserved bands. Used by the
    /// tests to assert the safety property directly.
    static func isClearOfReservedBands(_ frame: CGRect, in screenFrame: CGRect) -> Bool {
        let band = safeBand(in: screenFrame)
        return frame.minY >= band.minY && frame.maxY <= band.maxY
    }
}
