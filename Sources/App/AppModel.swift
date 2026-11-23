import AppKit
import Darwin
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Owns the long-lived objects and keeps preferences, lock state and the controller in step.
@MainActor
@Observable
final class AppModel {
    let preferences = Preferences()
    let artwork = ArtworkStore()
    let lyrics = LyricsStore()
    let controller: MediaController
    let lockState = LockStateMonitor()
    let spotifyAuth = SpotifyAuth()

    private(set) var lockScreenAvailability: LockScreenAvailability = .available

    @ObservationIgnored private let registry: ProviderRegistry
    @ObservationIgnored private var presenter: LockScreenPresenting?
    @ObservationIgnored private var notchPanel: NotchOverlayController?
    /// Keeps the app awake enough to keep polling while the screen is locked.
    @ObservationIgnored private var backgroundActivity: NSObjectProtocol?

    init() {
        registry = ProviderRegistry.standard(spotifyAuth: spotifyAuth)
        controller = MediaController(registry: registry)
        applyPreferences()
    }

    func start() {
        beginBackgroundActivity()
        makePresenter()
        notchPanel = NotchOverlayController(controller: controller, artwork: artwork, lyrics: lyrics,
                                            preferences: preferences)
        notchPanel?.show()
        GlobalShortcuts.register(controller: controller)

        lockState.onChange = { [weak self] in self?.lockStateChanged() }
        lockState.onReconcile = { [weak self] in self?.repairLockScreenIfNeeded() }
        lockStateChanged()

        controller.start()
    }

    /// Push settings into the controller and the presenter — one direction of flow only.
    func applyPreferences() {
        controller.autoDetect = preferences.autoDetectService
        controller.preferredProviderID = preferences.preferredProviderID
        lyrics.isEnabled = preferences.lyricsEnabled
    }

    /// Called when the Lock Screen position or display preferences change.
    func applyLockScreenPreferences() {
        presenter?.reconfigure()
        updateLockScreenVisibility()
    }

    var selectableProviders: [ProviderRegistry.Entry] { registry.selectableEntries }

    /// Bring a window forward from a menu-bar-only (accessory) app. Without the policy switch
    /// the window opens behind everything and can't take keyboard focus.
    func activateForWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The other half: go back to being an accessory once the window is gone, so a Dock icon
    /// doesn't linger for the rest of the session.
    func resignWindowActivation() {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Lock screen

    private func makePresenter() {
        let presenter = LockScreenPresenterFactory.make(
            content: { [weak self] screen, metrics, cardState in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    LockScreenView(
                        controller: self.controller,
                        artwork: self.artwork,
                        lyrics: self.lyrics,
                        metrics: metrics,
                        card: cardState,
                        preferences: self.preferences,
                        screenFrame: screen.frame,
                        cardPanelFrame: LockScreenLayout.frame(
                            for: self.preferences.lockScreenPosition,
                            in: screen.frame,
                            metrics: metrics
                        )
                    )
                )
            },
            preferences: preferences
        )
        self.presenter = presenter
        lockScreenAvailability = presenter.availability
    }

    private func lockStateChanged() {
        // Poll harder while the Lock Screen panel is on display, and not at all when the
        // displays are asleep — nobody can see the result.
        controller.pollingContext = lockState.pollingContext
        updateLockScreenVisibility()

        // Come back with fresh state the instant the screen lights up.
        if lockState.shouldShowLockScreenUI || !lockState.isLocked {
            Task { await controller.refreshNow() }
        }
    }

    private func updateLockScreenVisibility() {
        let shouldShow = preferences.lockScreenEnabled
            && (lockState.shouldShowLockScreenUI || LockScreenPreview.isEnabled)
        presenter?.setVisible(shouldShow)
        // `setVisible` early-returns when the value hasn't changed — which is exactly the case
        // after the displays wake, where the app never stopped believing it was visible but
        // the window server had already hidden our space. Re-assert whenever we should be up.
        if shouldShow { presenter?.reassertPersistently() }
    }

    /// The backstop for the same problem. The window server can hide our space without any
    /// notification firing at all, so the repair also rides the reconcile poll: two cheap
    /// window-server calls every few seconds, only while the card should be on screen, which
    /// bounds how long it can be missing to one pass.
    private func repairLockScreenIfNeeded() {
        guard preferences.lockScreenEnabled,
              lockState.shouldShowLockScreenUI || LockScreenPreview.isEnabled else { return }
        presenter?.reassert(.poll)
    }

    /// Without this, App Nap can throttle our timers to the point that the Lock Screen panel
    /// shows stale information. Explicitly *allows* idle system sleep — we don't want a media
    /// controller keeping the Mac awake.
    private func beginBackgroundActivity() {
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Monitoring playback state for the Lock Screen controller"
        )
    }
}

/// A lightweight hover panel aligned with the built-in MacBook camera notch.
@MainActor
private final class NotchOverlayController {
    private let controller: MediaController
    private let artwork: ArtworkStore
    private let lyrics: LyricsStore
    private let preferences: Preferences
    private let panel: NSPanel
    private var hosting: PassthroughHostingView<NotchPlayerView>?
    private(set) var expanded = false

    private let size = CGSize(width: 640, height: 220)
    private let closedSize: CGSize

    init(controller: MediaController, artwork: ArtworkStore, lyrics: LyricsStore,
         preferences: Preferences) {
        self.controller = controller
        self.artwork = artwork
        self.lyrics = lyrics
        self.preferences = preferences
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let left = screen.auxiliaryTopLeftArea?.width ?? (screen.frame.width / 2 - 92)
        let right = screen.auxiliaryTopRightArea?.width ?? (screen.frame.width / 2 - 92)
        let physicalNotchWidth = max(150, screen.frame.width - left - right + 4)
        // Reserve only enough vertical room for the attached mini player and transport row.
        closedSize = CGSize(width: max(200, physicalNotchWidth + 22),
                            height: max(50, screen.safeAreaInsets.top + 12))
        let frame = CGRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let host = PassthroughHostingView(rootView: NotchPlayerView(
            controller: controller, artwork: artwork, lyrics: lyrics, preferences: preferences,
            volumeManager: .shared,
            onExpand: { [weak self] value in self?.setExpanded(value) },
            closedSize: closedSize
        ))
        hosting = host
        host.frame = CGRect(origin: .zero, size: size)
        host.interactiveRect = { [weak self] in
            guard let self else { return nil }
            return self.expanded
                ? CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height)
                : CGRect(x: (self.size.width - self.closedSize.width) / 2, y: 0,
                         width: self.closedSize.width, height: self.closedSize.height)
        }
        panel.contentView = host
    }

    func show() {
        // The camera/notch is only present on supported MacBook displays.
        guard (NSScreen.main?.safeAreaInsets.top ?? 0) > 0 else { return }
        panel.orderFrontRegardless()
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        hosting?.rootView = NotchPlayerView(
            controller: controller, artwork: artwork, lyrics: lyrics, preferences: preferences,
            volumeManager: .shared,
            onExpand: { [weak self] value in self?.setExpanded(value) },
            expanded: value, closedSize: closedSize
        )
        hosting?.needsDisplay = true
    }
}

@MainActor
private struct NotchPlayerView: View {
    let controller: MediaController
    let artwork: ArtworkStore
    let lyrics: LyricsStore
    let preferences: Preferences
    @ObservedObject var volumeManager: BoringVolumeManager
    let onExpand: (Bool) -> Void
    var expanded = false
    let closedSize: CGSize
    @State private var tick = Date()
    @State private var brightness = Double(ScreenBrightness.current())
    @State private var brightnessLastChangeAt = Date.distantPast
    @State private var cursorInside = false
    @State private var showTray = false
    @State private var isDropTargeted = false
    @State private var showTrackInfo = true
    @State private var trayItems: [URL] = []

    private var playbackProgress: Double {
        guard let duration = controller.snapshot.track?.duration, duration > 0 else { return 0 }
        return min(1, max(0, controller.snapshot.interpolatedPosition(at: tick) / duration))
    }

    private var sensoryOverlay: (isBrightness: Bool, value: Double)? {
        guard preferences.sensoryOverlayStyle == .notch else { return nil }
        let now = Date()
        let duration = preferences.sensoryOverlayDuration
        let brightnessAge = now.timeIntervalSince(brightnessLastChangeAt)
        let volumeAge = now.timeIntervalSince(volumeManager.lastChangeAt)
        let brightnessIsRecent = preferences.brightnessOverlayEnabled && brightnessAge >= 0 && brightnessAge < duration
        let volumeIsRecent = preferences.volumeOverlayEnabled && volumeAge >= 0 && volumeAge < duration

        if brightnessIsRecent && (!volumeIsRecent || brightnessLastChangeAt > volumeManager.lastChangeAt) {
            return (true, brightness)
        }
        if volumeIsRecent { return (false, Double(volumeManager.rawVolume)) }
        return nil
    }

    @ViewBuilder private var brightnessSpark: some View {
        if brightness >= 0.995 {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: brightness)
                .offset(x: 8, y: -5)
        }
    }

    var body: some View {
        VStack(spacing: expanded ? 14 : 0) {
            if expanded {
                HStack(spacing: 10) {
                    ArtworkView(image: artwork.image, trackKey: controller.snapshot.track?.changeKey ?? "none", cornerRadius: 12, showsShadow: false)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        TrackMarquee(title: controller.snapshot.track?.title ?? "Nothing playing",
                                     artist: controller.snapshot.track?.artist ?? "Click for music controls",
                                     visible: showTrackInfo,
                                     onFinished: { withAnimation(.easeOut(duration: 0.3)) { showTrackInfo = false } })
                    }
                    Spacer(minLength: 6)
                    EqualizerBars(isPlaying: controller.snapshot.status.isPlaying,
                                  accent: artwork.accent)
                    Button { showTray.toggle() } label: {
                        Image(systemName: showTray ? "music.note" : "tray.full")
                    }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                    .help(showTray ? "Music player" : "File tray")
                }
                .frame(height: 64)
            } else {
                VStack(spacing: 1) {
                    HStack(spacing: 0) {
                        ArtworkView(image: artwork.image,
                                    trackKey: controller.snapshot.track?.changeKey ?? "none",
                                    cornerRadius: 5, showsShadow: false)
                            .frame(width: 26, height: 26)
                        Spacer(minLength: max(12, closedSize.width - 70))
                        EqualizerBars(isPlaying: controller.snapshot.status.isPlaying,
                                      accent: artwork.accent)
                    }
                    .frame(height: 28)
                    TrackMarquee(title: controller.snapshot.track?.title ?? "Nothing playing",
                                 artist: controller.snapshot.track?.artist ?? "Click to open",
                                 visible: showTrackInfo,
                                 onFinished: { withAnimation(.easeOut(duration: 0.3)) { showTrackInfo = false } })
                }
                .frame(maxWidth: .infinity)
            }

            if expanded {
                if showTray {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("File Tray").font(.headline)
                            Spacer()
                            Text("Drop files here to keep them handy")
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.horizontal, 4)
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(trayItems, id: \.absoluteString) { url in
                                    Button {
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        Label(url.lastPathComponent,
                                              systemImage: url.hasDirectoryPath ? "folder" : "doc")
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(.white.opacity(0.09), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL) }
                                    .contextMenu {
                                        ShareLink(item: url) {
                                            Label("Share…", systemImage: "airdrop")
                                        }
                                        Button("Remove from tray", systemImage: "xmark") {
                                            trayItems.removeAll { $0 == url }
                                            saveTrayItems()
                                        }
                                    }
                                }
                                if trayItems.isEmpty {
                                    Text("Your dropped files will appear here")
                                        .font(.callout).foregroundStyle(.white.opacity(0.5))
                                        .padding(.horizontal, 10)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 42)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .dropDestination(for: URL.self) { urls, _ in
                        let additions = urls.filter { !trayItems.contains($0) }
                        trayItems = Array((trayItems + additions).suffix(12))
                        saveTrayItems()
                        return !urls.isEmpty
                    }
                } else {
                if let lyric = lyrics.line(at: controller.snapshot.interpolatedPosition(at: tick))?.text {
                    Text(lyric)
                        .font(.system(size: 18, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 54)
                } else {
                    Text("Lyrics appear here when available")
                        .font(.callout).foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                HStack(spacing: 42) {
                    Button { controller.previous() } label: { Image(systemName: "backward.fill") }
                    Button { controller.togglePlayPause() } label: {
                        Image(systemName: controller.snapshot.status.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    Button { controller.next() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 42)
                VolumeSlider(volume: Int((volumeManager.rawVolume * 100).rounded()),
                             isMuted: volumeManager.isMuted,
                             accent: .accentColor,
                             onChange: { volumeManager.setAbsolute(Float32($0) / 100) },
                             onToggleMute: volumeManager.toggleMuteAction)
                    .frame(width: 210)
                HStack(spacing: 8) {
                    Image(systemName: "sun.min.fill").font(.caption)
                    Slider(value: $brightness, in: 0...1)
                        .onChange(of: brightness) { _, value in
                            ScreenBrightness.set(Float(value))
                            brightnessLastChangeAt = Date()
                        }
                        .tint(.accentColor)
                        .scaleEffect(brightness >= 0.995 ? 1.05 : 1)
                        .overlay(alignment: .trailing) { brightnessSpark }
                        .frame(width: 140)
                    Image(systemName: "sun.max.fill").font(.caption)
                }.foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, expanded ? 16 : 0)
        .padding(.top, expanded ? 10 : 0)
        .padding(.bottom, expanded ? 10 : 2)
        .foregroundStyle(.white)
        .frame(width: expanded ? 620 : closedSize.width,
               height: expanded ? 205 : closedSize.height, alignment: .top)
        .background(.black, in: UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: expanded ? 26 : 12,
            bottomTrailingRadius: expanded ? 26 : 12, topTrailingRadius: 0
        ))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: expanded ? 26 : 12,
                                       bottomTrailingRadius: expanded ? 26 : 12, topTrailingRadius: 0)
            .stroke(.white.opacity(expanded ? 0.12 : 0)))
        .frame(width: 640, height: 220, alignment: .top)
        .overlay(alignment: .top) {
            if !expanded, let overlay = sensoryOverlay {
                SensoryOverlayView(
                    isBrightness: overlay.isBrightness,
                    value: overlay.value,
                    labelStyle: preferences.sensoryLabelStyle,
                    accent: preferences.sensoryMatchSongColor ? artwork.accent : .white,
                    glassStyle: preferences.glassStyle
                )
                .offset(y: closedSize.height + 10)
                .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                        removal: .opacity))
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { onExpand(true) } }
        .onHover { inside in
            cursorInside = inside
            if expanded && !inside {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    if !cursorInside { onExpand(false) }
                }
            }
        }
        .dropDestination(for: URL.self, action: { urls, _ in
            addToTray(urls)
            showTray = true
            onExpand(true)
            return !urls.isEmpty
        }, isTargeted: { targeted in
            isDropTargeted = targeted
        })
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted {
                showTray = true
                onExpand(true)
            }
        }
        .onAppear {
            artwork.update(for: controller.snapshot.track)
            lyrics.update(for: controller.snapshot.track)
            trayItems = (UserDefaults.standard.stringArray(forKey: "LyricGlassTrayItems") ?? [])
                .compactMap(URL.init(string:))
        }
        .onChange(of: controller.snapshot.track?.changeKey) {
            artwork.update(for: controller.snapshot.track)
            lyrics.update(for: controller.snapshot.track)
            showTrackInfo = true
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { date in
            tick = date
            let actualBrightness = Double(ScreenBrightness.current())
            if abs(actualBrightness - brightness) > 0.015 {
                brightness = actualBrightness
                brightnessLastChangeAt = date
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: expanded)
        .animation(.easeInOut(duration: 0.18), value: sensoryOverlay?.isBrightness)
    }

    private func saveTrayItems() {
        UserDefaults.standard.set(trayItems.map(\.absoluteString), forKey: "LyricGlassTrayItems")
    }

    private func addToTray(_ urls: [URL]) {
        let additions = urls.filter { !trayItems.contains($0) }
        trayItems = Array((trayItems + additions).suffix(12))
        saveTrayItems()
    }
}

private struct EqualizerBars: View {
    let isPlaying: Bool
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { timeline in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * 7 + Double(index) * 1.15
                    Capsule()
                        .fill(accent.opacity(0.78 + 0.2 * abs(sin(phase * 0.23))))
                        .hueRotation(.degrees(22 * sin(phase * 0.15)))
                        .frame(width: 2, height: isPlaying ? 4 + abs(sin(phase)) * 11 : 3)
                }
            }
            .frame(width: 20, height: 24)
        }
    }
}

private struct TrackMarquee: View {
    let title: String
    let artist: String
    let visible: Bool
    let onFinished: () -> Void
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var didScroll = false

    var body: some View {
        GeometryReader { proxy in
            Text("\(title)   ·   \(artist)")
                .font(.system(size: 11, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { textProxy in
                        Color.clear.preference(key: NotchTextWidthKey.self, value: textProxy.size.width)
                    }
                }
                .offset(x: offset)
                .frame(height: proxy.size.height)
                .frame(maxWidth: .infinity, alignment: .center)
                .clipped()
                .opacity(visible ? 1 : 0)
                .onAppear { scrollOnce(viewport: proxy.size.width) }
                .onChange(of: title + artist) {
                    didScroll = false
                    offset = 0
                    scrollOnce(viewport: proxy.size.width)
                }
                .onPreferenceChange(NotchTextWidthKey.self) { contentWidth = $0 }
        }
        .frame(height: 18)
        .accessibilityLabel("\(title), \(artist)")
    }

    private func scrollOnce(viewport: CGFloat) {
        guard !didScroll else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard !didScroll else { return }
            didScroll = true
            let overflow = max(0, contentWidth - viewport + 8)
            guard overflow > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: onFinished)
                return
            }
            withAnimation(.linear(duration: min(3.4, max(1.4, Double(overflow / 48))))) {
                offset = -overflow
            }
            let duration = min(3.4, max(1.4, Double(overflow / 48)))
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                offset = 0
                onFinished()
            }
        }
    }
}

private struct NotchTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Controls the built-in display backlight using the same DisplayServices API that macOS
/// uses for its brightness keys. If the private symbol is unavailable, the slider remains
/// harmless and leaves the system brightness unchanged.
private enum ScreenBrightness {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    static func current() -> Float {
        guard let symbol = dlsym(framework, "DisplayServicesGetBrightness") else { return 0.5 }
        let function = unsafeBitCast(symbol, to: GetBrightness.self)
        var value: Float = 0.5
        guard function(CGMainDisplayID(), &value) == 0 else { return 0.5 }
        return min(max(value, 0), 1)
    }

    static func set(_ value: Float) {
        guard let symbol = dlsym(framework, "DisplayServicesSetBrightness") else { return }
        let function = unsafeBitCast(symbol, to: SetBrightness.self)
        _ = function(CGMainDisplayID(), min(max(value, 0), 1))
    }
}
