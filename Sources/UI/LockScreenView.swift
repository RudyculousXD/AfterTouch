import Combine
import SwiftUI

/// The controller drawn over the Lock Screen.
///
/// **Collapsed** is one unit: a single wide glass card with the artwork inset inside it.
/// **Expanded** detaches — the artwork lifts out of the card and stands on its own, bare,
/// above a player that keeps the card's width. Clicking the artwork moves between the two.
///
/// Both surfaces are placed by hand with `position` rather than by a stack, so each is one
/// continuously animating view: the card shrinks into the player while the artwork lifts out
/// of it and grows, and only the contents of the player crossfade. That is what makes it read
/// as one object coming apart rather than a second screen appearing. Only the artwork's own
/// shadow deepens as it detaches — it never gains a surface, so it reads as the album art
/// itself rather than a second card.
///
/// Always rendered dark: the lock screen sits over the user's wallpaper, so a light card would
/// glare and a system-appearance card would be unpredictable against arbitrary images.
struct LockScreenView: View {
    let controller: MediaController
    let artwork: ArtworkStore
    let lyrics: LyricsStore
    let metrics: LockScreenLayout.Metrics
    /// Expansion lives outside the view because `LockScreenPanel` has to know the current
    /// footprint at hit-test time. See `LockScreenCardState`.
    let card: LockScreenCardState
    let preferences: Preferences
    let screenFrame: CGRect
    let cardPanelFrame: CGRect

    @State private var now = Date()
    @State private var isHoveringArtwork = false
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var snapshot: PlayerSnapshot { controller.snapshot }
    private var track: Track? { snapshot.track }
    private var isExpanded: Bool { card.isExpanded && metrics.allowsExpansion }
    private var isLyricsMode: Bool { isExpanded && card.showsLyrics && preferences.lyricsEnabled }

    // MARK: - Geometry
    //
    // Everything below is expressed in the panel's coordinate space, which is the union of
    // both arrangements. `LockScreenLayout.Metrics` owns the sizes; this owns the placement.

    private var panel: CGSize { metrics.panelSize }
    /// The current arrangement's footprint inside the panel.
    private var footprint: CGRect { metrics.cardRect(expanded: card.isExpanded) }

    private var padding: CGFloat { LockScreenLayout.collapsedPadding }

    private var artworkSide: CGFloat {
        isExpanded ? metrics.expandedArtwork : LockScreenLayout.collapsedArtwork
    }

    /// Collapsed, the player surface *is* the whole card — it runs behind the artwork, which
    /// is why the two read as one unit. Expanded, it is only the part under the artwork.
    private var playerSize: CGSize {
        isExpanded
            ? CGSize(width: min(304, footprint.width), height: metrics.expandedPlayerHeight)
            : footprint.size
    }

    private var lyricColumnWidth: CGFloat {
        max(260, footprint.width - metrics.expandedArtwork
            - LockScreenLayout.expandedLyricsGap
            - LockScreenLayout.expandedLyricsTrailingInset)
    }

    private var artworkCenter: CGPoint {
        isExpanded
            ? CGPoint(
                x: isLyricsMode ? footprint.minX + 24 + artworkSide / 2 : footprint.midX,
                y: footprint.minY + 12 + artworkSide / 2
            )
            : CGPoint(
                // The artwork is drawn over the card rather than inside its stack, so it has
                // to use the same insets the stack does — the horizontal one on x, and the
                // (smaller) vertical one on y. Using the horizontal inset for both left it
                // sitting 10pt lower than the header row that reserves its place, which is
                // what pushed it onto the lyric line beneath.
                x: footprint.minX + padding + artworkSide / 2,
                y: footprint.minY + LockScreenLayout.collapsedPaddingVertical + artworkSide / 2
            )
    }

    private var playerCenter: CGPoint {
        isExpanded
            ? CGPoint(
                x: isLyricsMode ? artworkCenter.x : footprint.midX,
                y: artworkCenter.y + artworkSide / 2 + LockScreenLayout.surfaceGap + playerSize.height / 2
            )
            : CGPoint(x: footprint.midX, y: footprint.midY)
    }

    var body: some View {
        // Deliberately *not* wrapped in a `GlassEffectContainer`: the container composites its
        // merged glass pass above sibling views, which frosted the artwork sitting on top of
        // the collapsed card. Two independent glass surfaces render in the right order.
        ZStack(alignment: .topLeading) {
            backdrop
            topControls
            ZStack(alignment: .topLeading) {
                if isLyricsMode { expandedLyricsColumn }
                playerSurface
                artworkSurface
            }
            .frame(width: panel.width, height: panel.height)
            .scaleEffect(isExpanded ? 1 : preferences.lockScreenPlayerSize.scale)
            .position(x: cardOrigin.x + panel.width / 2, y: cardOrigin.y + panel.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .animation(Theme.Motion.expand, value: card.isExpanded)
        .onReceive(ticker) { now = $0 }
        .onChange(of: track?.changeKey) {
            artwork.update(for: track)
            lyrics.update(for: track)
        }
        .onAppear {
            artwork.update(for: track)
            lyrics.update(for: track)
        }
    }

    private var cardOrigin: CGPoint {
        CGPoint(x: cardPanelFrame.minX - screenFrame.minX,
                y: screenFrame.maxY - cardPanelFrame.maxY)
    }

    /// The small screen-corner controls shown in the reference. Lyrics is an independent
    /// layout switch; the close control returns to the compact player.
    private var topControls: some View {
        HStack(spacing: 3) {
            Button {
                withAnimation(Theme.Motion.expand) {
                    card.isExpanded = false
                    card.showsLyrics = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Collapse player")
            .accessibilityLabel("Collapse player")

            Button {
                withAnimation(Theme.Motion.morph) {
                    card.isExpanded = true
                    card.showsLyrics.toggle()
                }
            } label: {
                Image(systemName: card.showsLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(card.showsLyrics ? .white.opacity(0.18) : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(card.showsLyrics ? "Show player" : "Show lyrics")
            .accessibilityLabel(card.showsLyrics ? "Show player" : "Show lyrics")
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.black.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 1))
        .position(x: 60, y: 34)
        .environment(\.colorScheme, .dark)
    }

    /// The cover art fades into the wallpaper between the clock and sign-in areas. A soft
    /// mask avoids the hard horizontal seams that made the backdrop look like a tinted band.
    @ViewBuilder private var backdrop: some View {
        if preferences.lockScreenBackdrop != .off, let image = artwork.image {
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .blur(radius: preferences.lockScreenBackdrop.blurRadius)
                    .opacity(0.5)
                    .overlay(.black.opacity(preferences.lockScreenBackdropDim))
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Artwork surface

    private var artworkSurface: some View {
        Button(action: toggleExpansion) {
            ArtworkView(
                image: artwork.image,
                trackKey: track?.changeKey ?? "none",
                cornerRadius: isExpanded ? 22 : 16,
                showsShadow: isExpanded
            )
            .frame(width: artworkSide, height: artworkSide)
            .overlay(expansionAffordance)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!metrics.allowsExpansion)
        .onHover { isHoveringArtwork = $0 }
        .frame(width: artworkSide, height: artworkSide)
        .position(artworkCenter)
        .help(isExpanded ? "Collapse player" : "Expand player")
        .accessibilityLabel(isExpanded ? "Collapse player" : "Expand player")
    }

    /// A glass chip that fades in under the pointer. Nothing is drawn until the user shows
    /// interest, so the resting controller stays as quiet as the rest of the lock screen.
    @ViewBuilder private var expansionAffordance: some View {
        if metrics.allowsExpansion {
            Image(systemName: isExpanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(6)
                .playerGlass(style: preferences.glassStyle, cornerRadius: 9,
                             tint: artwork.accent, elevation: 0)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .opacity(isHoveringArtwork ? 1 : 0)
                .animation(Theme.Motion.control, value: isHoveringArtwork)
        }
    }

    private func toggleExpansion() {
        guard metrics.allowsExpansion else { return }
        withAnimation(Theme.Motion.expand) {
            card.isExpanded.toggle()
            if !card.isExpanded { card.showsLyrics = false }
        }
    }

    // MARK: - Player surface

    private var playerSurface: some View {
        ZStack {
            inlinePlayer.opacity(isExpanded ? 0 : 1)
            columnPlayer.opacity(isExpanded ? 1 : 0)
        }
        .frame(width: playerSize.width, height: playerSize.height)
        .playerGlass(
            style: preferences.glassStyle,
            cornerRadius: isExpanded
                ? Theme.Metrics.expandedCardCornerRadius
                : Theme.Metrics.cardCornerRadius,
            tint: artwork.accent,
            elevation: isExpanded ? 28 : 20
        )
        .position(playerCenter)
    }

    /// Lyrics sit beside the artwork while the player card stays tucked directly beneath it.
    private var expandedLyricsColumn: some View {
        lyricStack
            .frame(width: lyricColumnWidth, height: artworkSide, alignment: .leading)
            .position(
                x: artworkCenter.x + artworkSide / 2
                    + LockScreenLayout.expandedLyricsGap + lyricColumnWidth / 2,
                y: artworkCenter.y
            )
            .allowsHitTesting(false)
    }

    /// Collapsed: three rows, as the iOS Now Playing card has them. A header of artwork,
    /// title and artist with the output indicator in its top-right corner; the scrubber across
    /// the card's full width with its times flanking it; then the transport.
    ///
    /// The rows are separated by flexible spacers rather than fixed gaps so the card breathes
    /// into whatever height it is given, instead of stacking tightly at the top.
    private var inlinePlayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // The artwork is drawn by `artworkSurface` on top; this reserves its place.
                Color.clear.frame(
                    width: LockScreenLayout.collapsedArtwork,
                    height: LockScreenLayout.collapsedArtwork
                )
                metadata(alignment: .leading, showsDetail: false)
                // Wide enough that a long title truncates before it reaches the indicator.
                Spacer(minLength: 30)
            }
            .overlay(alignment: .topTrailing) { nowPlayingIndicator.padding(.top, 12) }

            lyricLine(alignment: .leading)

            Spacer(minLength: LockScreenLayout.collapsedRowGap)
            // Monochrome fill: the reference's bar is white, and the artwork's colour is
            // already carried by the tint of the card underneath it.
            scrubber(layout: .inline, accent: .white)
            Spacer(minLength: LockScreenLayout.collapsedRowGap)

            controlRow
        }
        .padding(.horizontal, padding)
        .padding(.vertical, LockScreenLayout.collapsedPaddingVertical)
        // Sized to the *current* surface, never its own arrangement's size: a child larger
        // than the frame would grow the stack and push the other arrangement out of the clip.
        .frame(width: playerSize.width, height: playerSize.height)
        .allowsHitTesting(!isExpanded)
    }

    /// Expanded: the same card, taller. The metadata, the monochrome scrubber and the control
    /// row are the collapsed card's, unchanged — the artwork has simply lifted out above them,
    /// and the volume the collapsed card had no room for has appeared below.
    ///
    /// Only two things differ, and both follow from the artwork having left the row: everything
    /// centres on the axis the detached artwork now defines, and the metadata gains the album
    /// and service line the collapsed card is too short to carry.
    private var columnPlayer: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                ArtworkView(image: artwork.image, trackKey: track?.changeKey ?? "none",
                            cornerRadius: 8, showsShadow: false)
                    .frame(width: 42, height: 42)
                metadata(alignment: .leading, showsDetail: false)
                Spacer(minLength: 4)
                nowPlayingIndicator
            }
            scrubber(layout: .inline, accent: .white)
            expandedControlRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: playerSize.width, height: playerSize.height)
        .allowsHitTesting(isExpanded)
    }

    /// The detached card uses only the controls shown in the reference: favourite and
    /// transport, with the play/pause group held on the card's centre line.
    private var expandedControlRow: some View {
        HStack {
            if controller.capabilities.contains(.favorite) {
                let liked = track?.isFavorite ?? false
                utilityToggle(
                    liked ? "heart.fill" : "heart",
                    isOn: liked,
                    tint: .pink,
                    label: liked ? "Remove from favourites" : "Add to favourites",
                    action: controller.toggleFavorite
                )
                .disabled(track == nil)
            }
            Spacer(minLength: 0)
        }
        .overlay { transport(size: .card, style: .plain) }
        .frame(height: TransportControls.Size.card.primary)
    }

    /// Three adjacent timed lines keep the current lyric bright and the surrounding lines
    /// available at a glance, matching the reference's line-by-line karaoke treatment.
    @ViewBuilder private var lyricStack: some View {
        let synced = lyrics.syncedLyrics
        let activeIndex = synced?.index(at: playbackPosition)
        if let synced, let activeIndex {
            VStack(spacing: 14) {
                ForEach(max(0, activeIndex - 2)...min(synced.lines.count - 1, activeIndex + 2), id: \.self) { index in
                    let text = synced.lines[index].text
                    if index == activeIndex {
                        lyricFill(text: text, start: synced.lines[index].time,
                                  end: index + 1 < synced.lines.count ? synced.lines[index + 1].time : synced.lines[index].time + 3,
                                  fontSize: 24)
                    } else {
                        Text(text).foregroundStyle(.white.opacity(0.38))
                            .font(.system(size: 19, weight: .semibold)).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            lyricLine(alignment: .center)
        }
    }

    // MARK: - Lyrics

    /// Collapsed: the line being sung, and nothing else. A Lock Screen card is read from across
    /// a room, so one line at a size that carries is worth more than a paragraph that doesn't.
    /// Absent entirely — not an empty row — when there is nothing timed to show, so the card
    /// keeps its usual proportions for tracks with no lyrics.
    @ViewBuilder private func lyricLine(alignment: HorizontalAlignment) -> some View {
        if lyrics.isEnabled {
            // The row is present for the whole track, empty or not. Appearing only once the
            // lookup returned made every row below it jump a few seconds into the song, which
            // is worse than a blank strip on the tracks that have no lyrics.
            let index = lyrics.syncedLyrics?.index(at: playbackPosition)
            let line = index.flatMap { lyrics.syncedLyrics?.lines[$0] }
            let text = line?.text ?? ""
            let nextTime = index.flatMap { i in
                lyrics.syncedLyrics?.lines.dropFirst(i + 1).first?.time
            }
            let start = line?.time ?? playbackPosition
            let end = max(start + 1, nextTime ?? start + max(2, Double(text.count) * 0.12))
            let fill = text.isEmpty ? 0 : min(1, max(0, (playbackPosition - start) / (end - start)))
            lyricFill(text: text, start: start, end: end, fontSize: 13)
                .animation(.linear(duration: 0.5), value: fill)
                .frame(height: Self.lyricLineHeight)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
                .accessibilityLabel(text.isEmpty ? "No lyrics" : "Lyric: \(text)")
        }
    }

    private func lyricFill(text: String, start: TimeInterval, end: TimeInterval, fontSize: CGFloat) -> some View {
        let fill = min(1, max(0, (playbackPosition - start) / max(1, end - start)))
        return ZStack(alignment: .leading) {
            Text(text).foregroundStyle(.white.opacity(0.38))
            Text(text).foregroundStyle(.white)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle().frame(width: proxy.size.width * (preferences.lyricFillEnabled ? fill : 1))
                    }
                }
                .animation(.linear(duration: 0.5), value: fill)
        }
            .font(.system(size: fontSize, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
    }

    private static let lyricLineHeight: CGFloat = 18

    /// Expanded: the sheet around the current line, which scrolls itself as the song moves.
    /// Deliberately not interactive — the panel takes mouse events but the card is something
    /// you glance at, and a scroll view that fights the playback position is worse than one
    /// that simply follows it.
    /// One interpolated reading per render, shared by both lyric views and matching the
    /// scrubber exactly — two independent interpolations would drift apart on screen.
    private var playbackPosition: TimeInterval {
        snapshot.interpolatedPosition(at: now)
    }

    /// The reference card's top-right glyph. It carries real state rather than decoration:
    /// bright and animating while something is playing, dimmed when it isn't — which the card
    /// otherwise says only through a pause glyph small enough to miss at a glance.
    private var nowPlayingIndicator: some View {
        let playing = snapshot.status.isPlaying
        return Image(systemName: "waveform")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white.opacity(playing ? 0.95 : 0.3))
            .symbolEffect(.variableColor.iterative, isActive: playing)
            .animation(Theme.Motion.control, value: playing)
            .help(playing ? "Playing in \(controller.activeProviderName)" : "Paused")
            .accessibilityHidden(true)
    }

    /// The control row, identical in both arrangements: transport on the card's centre line,
    /// utilities pinned to the edges. Centring is an overlay rather than a pair of flanking
    /// spacers so the play button stays put whatever mix of utilities the active provider
    /// supports — and, expanding, so it stays on the axis of the artwork above it.
    ///
    /// The reference puts AirPlay in the trailing slot. Nocta has no output routing to give
    /// it, so the slot carries the nearest control it genuinely has and stays empty when the
    /// provider can't do that either — an empty corner rather than a dead icon.
    private var controlRow: some View {
        let caps = controller.capabilities
        return HStack(spacing: 2) {
            if caps.contains(.shuffle) {
                utilityToggle(
                    "shuffle",
                    isOn: snapshot.isShuffling,
                    label: snapshot.isShuffling ? "Shuffle on" : "Shuffle off",
                    action: controller.toggleShuffle
                )
            }
            if caps.contains(.repeatMode) {
                utilityToggle(
                    snapshot.repeatMode == .one ? "repeat.1" : "repeat",
                    isOn: snapshot.repeatMode != .off,
                    label: "Repeat \(snapshot.repeatMode.rawValue)",
                    action: controller.cycleRepeat
                )
            }

            Spacer(minLength: 0)

            if caps.contains(.favorite) {
                let liked = track?.isFavorite ?? false
                utilityToggle(
                    liked ? "heart.fill" : "heart",
                    isOn: liked,
                    tint: .pink,
                    label: liked ? "Remove from favourites" : "Add to favourites",
                    action: controller.toggleFavorite
                )
                .disabled(track == nil)
            }
        }
        .overlay { transport(size: .card, style: .plain) }
        .frame(height: TransportControls.Size.card.primary)
    }

    /// A utility glyph: the same bare treatment as the transport beside it, so the row reads
    /// as one set of controls rather than chrome flanking a transport.
    private func utilityToggle(
        _ symbol: String,
        isOn: Bool,
        tint: Color? = nil,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(PlainControlStyle(diameter: 30))
        .foregroundStyle(isOn ? (tint ?? artwork.accent) : Color.white.opacity(0.5))
        .help(label)
        .accessibilityLabel(label)
    }

    /// The one control the expanded arrangement adds. White rather than tinted, like the
    /// scrubber above it and for the same reason: the artwork's colour is already carried by
    /// the card's tint, and a second coloured rail would compete with it.
    ///
    /// Absent entirely when the provider has no volume — an empty gap, never a dead slider.
    @ViewBuilder private var volumeRow: some View {
        if controller.capabilities.contains(.volume) {
            VolumeSlider(
                volume: snapshot.volume,
                isMuted: snapshot.isMuted,
                accent: .white,
                onChange: controller.setVolume,
                onToggleMute: controller.toggleMute
            )
            .frame(width: 190, height: 22)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func metadata(alignment: HorizontalAlignment, showsDetail: Bool) -> some View {
        let frameAlignment: Alignment = alignment == .center ? .center : .leading
        if let track {
            VStack(alignment: alignment, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                if showsDetail {
                    Text(detailLine(for: track))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: alignment == .center ? .infinity : nil, alignment: frameAlignment)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .id(track.changeKey)
            .transition(.opacity)
            .animation(Theme.Motion.trackChange, value: track.changeKey)
        } else {
            VStack(alignment: alignment, spacing: 2) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                Text(emptyDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
            }
            .frame(maxWidth: alignment == .center ? .infinity : nil, alignment: frameAlignment)
        }
    }

    /// Album and service share a line in the expanded player — the album alone left the
    /// service nowhere to go, and a fourth line of text cost more height than it was worth.
    private func detailLine(for track: Track) -> String {
        track.album.isEmpty
            ? controller.activeProviderName
            : "\(track.album) · \(controller.activeProviderName)"
    }

    /// The Lock Screen has no room for a full error UI, so the empty state carries the
    /// specific reason rather than a generic message.
    private var emptyDetail: String {
        switch controller.status {
        case .appNotRunning(let app):    "\(app) isn't running."
        case .permissionDenied(let app): "Nocta can't control \(app)."
        case .error(let message):        message
        case .connected, .nothingPlaying: "Start something in Spotify or Music."
        }
    }

    private func scrubber(layout: ScrubberView.Layout, accent: Color) -> some View {
        ScrubberView(
            position: snapshot.interpolatedPosition(at: now),
            duration: track?.duration ?? 0,
            accent: accent,
            isSeekable: controller.capabilities.contains(.seek),
            layout: layout,
            onSeek: controller.seek(to:)
        )
    }

    private func transport(
        size: TransportControls.Size,
        style: TransportControls.Style = .circular
    ) -> some View {
        TransportControls(
            isPlaying: snapshot.status.isPlaying,
            accent: artwork.accent,
            size: size,
            style: style,
            onPrevious: controller.previous,
            onPlayPause: controller.togglePlayPause,
            onNext: controller.next
        )
    }
}
