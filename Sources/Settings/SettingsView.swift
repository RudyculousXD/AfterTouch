import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("LyricGlass") {
                    ForEach(SettingsSection.primary) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                }
                Section("More") {
                    ForEach(SettingsSection.more) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 225)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general: GeneralSettings(model: model)
                case .music: ServiceSettings(model: model)
                case .lockScreen: LockScreenSettings(model: model)
                case .sensory: SensorySettings(model: model)
                case .appearance: AppearanceSettings(model: model)
                case .shortcuts: ShortcutSettings(model: model)
                case .about: AboutSettings(model: model)
                }
            }
            .navigationTitle((selection ?? .general).title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 560)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, music, lockScreen, sensory, appearance, shortcuts, about
    var id: Self { self }

    static let primary: [Self] = [.general, .music, .lockScreen, .sensory, .appearance]
    static let more: [Self] = [.shortcuts, .about]

    var title: String {
        switch self {
        case .general: "General"
        case .music: "Music Service"
        case .lockScreen: "Lock Screen"
        case .sensory: "Sensory"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .music: "music.note"
        case .lockScreen: "lock.display"
        case .sensory: "speaker.wave.2"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

private struct GeneralSettings: View {
    let model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    if case .failure(let error) = LaunchAtLogin.set(enabled) {
                        launchError = error.localizedDescription
                        launchAtLogin = LaunchAtLogin.isEnabled
                    } else {
                        launchError = nil
                    }
                }
            if LaunchAtLogin.requiresApproval {
                Text("macOS needs you to approve Nocta in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }

            Toggle("Start minimised to the menu bar",
                   isOn: Bindable(model.preferences).startMinimized)
            Toggle("Show menu-bar icon",
                   isOn: Bindable(model.preferences).showMenuBarIcon)
        }
        .formStyle(.grouped)
        .settingsGlass(model.preferences.glassStyle)
    }
}

private struct ServiceSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Toggle("Automatically detect the active player",
                   isOn: Bindable(model.preferences).autoDetectService)
                .onChange(of: model.preferences.autoDetectService) { model.applyPreferences() }

            Picker("Music service", selection: Bindable(model.preferences).preferredProvider) {
                ForEach(model.selectableProviders, id: \.id.rawValue) { entry in
                    Text(entry.displayName).tag(entry.id.rawValue)
                }
            }
            .disabled(model.preferences.autoDetectService)
            .onChange(of: model.preferences.preferredProvider) { model.applyPreferences() }

            Section {
                Text("Nocta controls whichever app is playing on this Mac using Apple Events. "
                     + "It never launches Spotify or Music on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Spotify account (advanced, optional)") {
                SpotifyAccountControls(model: model)
            }

            Section("What this service supports") {
                CapabilityRow(title: "Seek", enabled: model.controller.capabilities.contains(.seek))
                CapabilityRow(title: "Volume", enabled: model.controller.capabilities.contains(.volume))
                CapabilityRow(title: "Native mute", enabled: model.controller.capabilities.contains(.nativeMute))
                CapabilityRow(title: "Shuffle", enabled: model.controller.capabilities.contains(.shuffle))
                CapabilityRow(title: "Repeat", enabled: model.controller.capabilities.contains(.repeatMode))
                CapabilityRow(title: "Repeat one", enabled: model.controller.capabilities.contains(.repeatOne))
                CapabilityRow(title: "Favourite", enabled: model.controller.capabilities.contains(.favorite))
            }
        }
        .formStyle(.grouped)
        .settingsGlass(model.preferences.glassStyle)
    }
}

/// Optional Web API sign-in. Only needed for Spotify's "like", which has no Apple Events
/// equivalent. Everything else works signed out.
private struct SpotifyAccountControls: View {
    let model: AppModel
    @State private var isConnecting = false

    var body: some View {
        if model.spotifyAuth.isConnected {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                Text("Connected")
                Spacer()
                Button("Disconnect") { model.spotifyAuth.disconnect() }
            }
        } else {
            TextField("Spotify client ID", text: Bindable(model.spotifyAuth).clientID,
                      prompt: Text("Paste your client ID"))
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(isConnecting ? "Connecting…" : "Connect Spotify") {
                    isConnecting = true
                    Task {
                        await model.spotifyAuth.connect()
                        isConnecting = false
                    }
                }
                .disabled(model.spotifyAuth.clientID.isEmpty || isConnecting)
                Spacer()
                Link("Create one",
                     destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    .font(.caption)
            }

            Text("Advanced — most people should skip this. Everything else already works "
                 + "without it: play/pause, skip, seek, volume, shuffle and repeat need no "
                 + "account and no Premium.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Signing in adds two things — liking a Spotify track, and the repeat-one "
                 + "position on the repeat button. Spotify allows both only through its Web "
                 + "API, and only for an app you register yourself: register one on Spotify's "
                 + "dashboard with redirect URI nocta://spotify-callback, tick Web API, and add "
                 + "your account under User Management. Since March 2026 that account must have "
                 + "Spotify Premium, or every request is refused.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Tokens are stored in your Keychain, never on disk in plain text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let error = model.spotifyAuth.lastError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let enabled: Bool

    var body: some View {
        HStack {
            Image(systemName: enabled ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(enabled ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            if !enabled {
                Text("not supported").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LockScreenSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: model.lockScreenAvailability.isAvailable
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.lockScreenAvailability.isAvailable
                                         ? Color.green : Color.orange)
                    Text(model.lockScreenAvailability.explanation)
                        .font(.callout)
                }
            }

            Toggle("Show controls on the Lock Screen",
                   isOn: Bindable(model.preferences).lockScreenEnabled)
                .disabled(!model.lockScreenAvailability.isAvailable)
                .onChange(of: model.preferences.lockScreenEnabled) {
                    model.applyLockScreenPreferences()
                }

            Picker("Position", selection: Bindable(model.preferences).lockScreenPosition) {
                ForEach(LockScreenPosition.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!model.preferences.lockScreenEnabled || !model.lockScreenAvailability.isAvailable)
            .onChange(of: model.preferences.lockScreenPosition) {
                model.applyLockScreenPreferences()
            }

            Toggle("Show on all displays",
                   isOn: Bindable(model.preferences).lockScreenAllDisplays)
                .disabled(!model.preferences.lockScreenEnabled || !model.lockScreenAvailability.isAvailable)
                .onChange(of: model.preferences.lockScreenAllDisplays) {
                    model.applyLockScreenPreferences()
                }

            Section("Look") {
                Picker("Artwork background",
                       selection: Bindable(model.preferences).lockScreenBackdrop) {
                    ForEach(LockScreenBackdrop.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .onChange(of: model.preferences.lockScreenBackdrop) {
                    model.applyLockScreenPreferences()
                }

                if model.preferences.lockScreenBackdrop != .off {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Darken background")
                            Spacer()
                            Text("\(Int(model.preferences.lockScreenBackdropDim * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Bindable(model.preferences).lockScreenBackdropDim, in: 0...0.75)
                            .onChange(of: model.preferences.lockScreenBackdropDim) {
                                model.applyLockScreenPreferences()
                            }
                    }
                }

                Picker("Player size", selection: Bindable(model.preferences).lockScreenPlayerSize) {
                    ForEach(LockScreenPlayerSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .onChange(of: model.preferences.lockScreenPlayerSize) {
                    model.applyLockScreenPreferences()
                }
            }

            Section("Lyrics") {
                Toggle("Show lyrics on the card",
                       isOn: Bindable(model.preferences).lyricsEnabled)
                    .onChange(of: model.preferences.lyricsEnabled) {
                        model.applyPreferences()
                        // The expanded card reserves height for the sheet, so the panel has to
                        // be re-measured when this changes.
                        model.applyLockScreenPreferences()
                    }

                Toggle("Fill lyrics as they’re sung",
                       isOn: Bindable(model.preferences).lyricFillEnabled)
                    .disabled(!model.preferences.lyricsEnabled)

                Text("The lyric fill is estimated from the time between lyric lines. Exact "
                     + "word or syllable timestamps are not included in the available lyric data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Lyric lookup contacts LRCLIB. When enabled, the playing track's "
                     + "title, artist, album and length are sent to lrclib.net to look up "
                     + "timed lyrics — nothing else, and nothing that identifies you or your "
                     + "account. Turn lyric lookup off to stop these requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Lyrics come from LRCLIB, a free community-contributed database. Coverage "
                     + "is good but not complete, and tracks without an entry simply show no "
                     + "lyric line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Positions are constrained so the controller never covers the password "
                     + "field, Touch ID prompt or user picker. By design Nocta cannot "
                     + "receive keyboard input while the Mac is locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsGlass(model.preferences.glassStyle)
    }
}

private struct SensorySettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Style") {
                Picker("Show feedback in", selection: Bindable(model.preferences).sensoryOverlayStyle) {
                    ForEach(SensoryOverlayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Overlays") {
                Toggle("Brightness", isOn: Bindable(model.preferences).brightnessOverlayEnabled)
                    .disabled(model.preferences.sensoryOverlayStyle == .system)
                Toggle("Volume", isOn: Bindable(model.preferences).volumeOverlayEnabled)
                    .disabled(model.preferences.sensoryOverlayStyle == .system)
            }

            Section("Appearance") {
                Toggle("Match song color", isOn: Bindable(model.preferences).sensoryMatchSongColor)
                    .disabled(model.preferences.sensoryOverlayStyle == .system)

                Picker("Label style", selection: Bindable(model.preferences).sensoryLabelStyle) {
                    ForEach(SensoryLabelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.preferences.sensoryOverlayStyle == .system)
            }

            Section("Timing") {
                HStack {
                    Text("Overlay duration")
                    Spacer()
                    Text("\(model.preferences.sensoryOverlayDuration, specifier: "%.1f") sec")
                        .foregroundStyle(.secondary)
                }
                Slider(value: Bindable(model.preferences).sensoryOverlayDuration, in: 1...6, step: 0.5)
                    .disabled(model.preferences.sensoryOverlayStyle == .system)
            }

            Section {
                Text("Notch feedback appears briefly when the built-in display brightness or output volume changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsGlass(model.preferences.glassStyle)
    }
}

private struct AppearanceSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("macOS appearance") {
                Picker("Appearance", selection: Bindable(model.preferences).appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Player surfaces") {
                Text("Choose how the player and Lock Screen card look.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(GlassStyle.allCases) { style in
                        Button {
                            model.preferences.glassStyle = style
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(style == .clearOpaque
                                          ? Color.black.opacity(0.94)
                                          : Color.accentColor.opacity(style == .liquidGlass ? 0.16 : 0.30))
                                    .overlay {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(style == .clearOpaque ? .white : .primary)
                                    }
                                    .playerGlass(style: style, cornerRadius: 11,
                                                tint: .accentColor, elevation: 0)
                                    .frame(height: 58)

                                Text(style.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(style.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(model.preferences.glassStyle == style
                                          ? Color.accentColor.opacity(0.10) : Color.clear)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(model.preferences.glassStyle == style
                                                  ? Color.accentColor.opacity(0.8)
                                                  : Color.secondary.opacity(0.18), lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.preferences.glassStyle == style ? .isSelected : [])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsGlass(model.preferences.glassStyle)
    }
}

private struct ShortcutSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Play / Pause", name: .playPause)
                KeyboardShortcuts.Recorder("Next track", name: .nextTrack)
                KeyboardShortcuts.Recorder("Previous track", name: .previous)
                KeyboardShortcuts.Recorder("Volume up", name: .volumeUp)
                KeyboardShortcuts.Recorder("Volume down", name: .volumeDown)
                KeyboardShortcuts.Recorder("Mute", name: .mute)
            }

            Section {
                Text("No shortcuts are set by default, so nothing conflicts with existing macOS "
                     + "shortcuts unless you choose it. These do not fire while the Mac is "
                     + "locked — macOS reserves keyboard input for the login window, so use "
                     + "the on-screen Lock Screen controls instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsGlass(model.preferences.glassStyle)
    }
}

private struct AboutSettings: View {
    let model: AppModel
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("LyricGlass").font(.title2.weight(.semibold))
            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
            Link("Project page", destination: URL(string: "https://example.com/nocta")!)
                .font(.caption)
            Text("Lock Screen rendering relies on private macOS APIs and may stop working in a "
                 + "future macOS release. See docs/LOCK_SCREEN.md for exactly which APIs are "
                 + "public, undocumented, and private.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .playerGlass(style: model.preferences.glassStyle, cornerRadius: 24,
                     tint: .accentColor, elevation: 0)
        .padding(14)
    }
}

private extension View {
    func settingsGlass(_ style: GlassStyle) -> some View {
        scrollContentBackground(.hidden)
            .background(Color.clear)
            .playerGlass(style: style, cornerRadius: 24, tint: .accentColor, elevation: 0)
            .padding(14)
    }
}
