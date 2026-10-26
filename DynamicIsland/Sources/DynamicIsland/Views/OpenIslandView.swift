import SwiftUI

struct OpenIslandView: View {
    let namespace: Namespace.ID
    @Environment(IslandModel.self) private var model
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                switch model.currentTab {
                case .media:
                    MediaTab(namespace: namespace)
                        .transition(.islandContent(scale: 0.97))
                case .home:
                    HomeTab()
                        .transition(.islandContent(scale: 0.97))
                case .hub:
                    HubTab()
                        .transition(.islandContent(scale: 0.97))
                case .tray:
                    TrayTab()
                        .transition(.islandContent(scale: 0.97))
                case .clipboard:
                    ClipboardTab()
                        .transition(.islandContent(scale: 0.97))
                case .posture:
                    PostureTab()
                        .transition(.islandContent(scale: 0.97))
                case .controls:
                    ControlsTab()
                        .transition(.islandContent(scale: 0.97))
                }
            }
            .padding(.horizontal, IslandLayout.contentPadding)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, model.earRadius)
    }

    /// Tabs left of the camera, the rest – and the gear – right of it, so none hide under the notch.
    private var header: some View {
        let tabs = visibleTabs
        let leftCount = min(tabs.count, maxTabsPerSide)
        return HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(tabs.prefix(leftCount), id: \.tab) { item in
                    tabButton(item.tab, symbol: item.symbol, help: item.help, badge: item.badge)
                }
            }
            Spacer(minLength: model.notch.width + 12)
            HStack(spacing: 2) {
                ForEach(tabs.dropFirst(leftCount), id: \.tab) { item in
                    tabButton(item.tab, symbol: item.symbol, help: item.help, badge: item.badge)
                }
                Button { model.onOpenSettings?() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 26))
                .help("Inställningar")
            }
        }
        .padding(.horizontal, IslandLayout.contentPadding - 6)
        .frame(height: model.notch.height)
    }

    private struct TabItem {
        let tab: IslandTab
        let symbol: String
        let help: String
        var badge = 0
    }

    private var visibleTabs: [TabItem] {
        var tabs = [TabItem(tab: .media, symbol: "music.note", help: "Spelas nu")]
        if model.showsHubTab {
            tabs.append(TabItem(tab: .hub, symbol: "checklist", help: "Acord Hub", badge: model.hub.unreadCount))
        }
        if model.settings.showClipboardTab {
            tabs.append(TabItem(tab: .clipboard, symbol: "doc.on.clipboard.fill", help: "Urklippskö"))
        }
        if model.settings.showTrayTab {
            tabs.append(TabItem(tab: .tray, symbol: model.tray.items.isEmpty ? "tray.fill" : "tray.full.fill", help: "Tray"))
        }
        if model.settings.showHomeTab { tabs.append(TabItem(tab: .home, symbol: "house.fill", help: "Hem")) }
        tabs.append(TabItem(tab: .controls, symbol: "switch.2", help: "Ljud och skärm"))
        if model.showsPostureTab { tabs.append(TabItem(tab: .posture, symbol: "figure.stand", help: "Hållning")) }
        return tabs
    }

    /// How many 34 pt tab buttons fit beside the camera.
    private var maxTabsPerSide: Int {
        let side = (model.openWidth - model.notch.width) / 2 - IslandLayout.contentPadding
        return max(Int(side / 36), 2)
    }

    private func tabButton(_ tab: IslandTab, symbol: String, help: String, badge: Int = 0) -> some View {
        let isSelected = model.currentTab == tab
        return Button { model.select(tab) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.45))
                .frame(width: 34, height: 22)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "tab", in: tabNamespace)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                            .offset(x: -6, y: 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(badge > 0 ? "\(help) – \(badge) olästa" : help)
    }
}

// MARK: - Media

private struct MediaTab: View {
    let namespace: Namespace.ID
    @Environment(IslandModel.self) private var model
    @State private var scrubPosition: Double?

    private let artworkSize: CGFloat = 80
    private let sideColumn: CGFloat = 36

    var body: some View {
        let media = model.media
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: media.hasMedia ? media.title : "Inget spelas",
                                font: .system(size: 15, weight: .semibold))
                    MarqueeText(text: media.hasMedia ? media.subtitle : "Spela något i valfri app",
                                font: .system(size: 13), color: .white.opacity(0.55))
                    Spacer(minLength: 0)
                    transportControls
                }
                .padding(.top, 4)
                VStack {
                    EqualizerView(color: media.accentColor, isPlaying: media.isPlaying, height: 14)
                        .opacity(media.hasMedia ? 1 : 0)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    outputButton
                }
                .frame(width: sideColumn)
            }
            .frame(height: artworkSize)
            .padding(.top, 4)

            progressRow
                .frame(height: 18)
                .padding(.top, 14)
            volumeRow
                .frame(height: 18)
                .padding(.top, 8)
        }
    }

    private var artwork: some View {
        let media = model.media
        return ArtworkView(image: media.artwork, version: media.artworkVersion, size: artworkSize, cornerRadius: 14)
            .matchedGeometryEffect(id: "artwork", in: namespace)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            .overlay(alignment: .bottomTrailing) {
                if let icon = media.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .offset(x: 7, y: 7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onTapGesture { media.openPlayer() }
            .help(media.bundleIdentifier == nil ? "" : "Öppna spelaren")
    }

    private var transportControls: some View {
        let media = model.media
        return HStack(spacing: 6) {
            Button { media.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            .buttonStyle(IslandButtonStyle(diameter: 32))

            Button { media.togglePlayPause() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 21))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .buttonStyle(IslandButtonStyle(diameter: 36))

            Button { media.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
            .buttonStyle(IslandButtonStyle(diameter: 32))
        }
        .padding(.leading, -8)
        .disabled(!media.hasMedia)
    }

    private var outputButton: some View {
        Button { model.select(.controls) } label: {
            Image(systemName: model.audio.currentDevice?.symbolName ?? "airplayaudio")
                .font(.system(size: 14, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IslandButtonStyle(diameter: 30))
        .help(model.audio.currentDevice?.name ?? "Ljudutgång")
    }

    private var progressRow: some View {
        let media = model.media
        return TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = media.duration
            let elapsed = scrubPosition ?? media.elapsed(at: context.date)
            HStack(spacing: 10) {
                Text(duration > 0 ? formatTime(elapsed) : "--:--")
                    .frame(width: sideColumn, alignment: .trailing)
                ElasticSlider(
                    value: Binding(get: { duration > 0 ? elapsed / duration : 0 },
                                   set: { scrubPosition = $0 * duration }),
                    onEditingChanged: { editing in
                        if !editing, let position = scrubPosition {
                            media.seek(to: position)
                            scrubPosition = nil
                        }
                    }
                )
                .disabled(duration <= 0)
                Text(duration > 0 ? "-" + formatTime(max(duration - elapsed, 0)) : "--:--")
                    .frame(width: sideColumn, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var volumeRow: some View {
        let audio = model.audio
        return HStack(spacing: 10) {
            Button { audio.toggleMute() } label: {
                Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 11))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: sideColumn, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ElasticSlider(value: Binding(get: { audio.isMuted ? 0 : audio.volume }, set: { audio.setVolume($0) }))
                .disabled(!audio.canSetVolume)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .frame(width: sideColumn, alignment: .leading)
        }
        .foregroundStyle(.white.opacity(0.5))
    }
}

// MARK: - Sound & display

private struct ControlsTab: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let audio = model.audio
        let brightness = model.brightness
        VStack(alignment: .leading, spacing: 0) {
            if model.settings.showTemperature && model.thermal.isAvailable {
                TemperatureRow()
                    .frame(height: IslandLayout.temperatureRowHeight)
                    .padding(.bottom, 8)
            }
            SliderRow(
                symbol: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                variableValue: audio.isMuted ? 0 : audio.volume,
                value: Binding(get: { audio.isMuted ? 0 : audio.volume }, set: { audio.setVolume($0) }),
                symbolAction: { audio.toggleMute() }
            )
            .disabled(!audio.canSetVolume)
            .frame(height: IslandLayout.sliderRowHeight)

            if brightness.isAvailable {
                SliderRow(
                    symbol: "sun.max.fill",
                    variableValue: brightness.brightness,
                    value: Binding(get: { brightness.brightness }, set: { brightness.setBrightness($0) })
                )
                .frame(height: IslandLayout.sliderRowHeight)
            }

            Text("Ljudutgång")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: IslandLayout.sectionHeaderHeight, alignment: .bottomLeading)
                .padding(.top, 8)

            Group {
                if audio.devices.count > IslandLayout.maxVisibleDevices {
                    IslandScroll { deviceList }
                } else {
                    deviceList
                }
            }
            .frame(height: CGFloat(min(audio.devices.count, IslandLayout.maxVisibleDevices)) * IslandLayout.deviceRowHeight,
                   alignment: .top)
            .padding(.horizontal, -6)
        }
        .padding(.top, 4)
    }

    private var deviceList: some View {
        let audio = model.audio
        return VStack(spacing: 0) {
            ForEach(audio.devices) { device in
                OutputDeviceRow(device: device, isSelected: device.id == audio.currentDeviceID) {
                    audio.selectDevice(device)
                }
            }
        }
    }
}

private struct SliderRow: View {
    var symbol: String
    var variableValue: Double
    @Binding var value: Double
    var symbolAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button { symbolAction?() } label: {
                Image(systemName: symbol, variableValue: variableValue)
                    .font(.system(size: 13, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(symbolAction != nil)
            .foregroundStyle(.white.opacity(0.85))

            ElasticSlider(value: $value)

            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 26, alignment: .trailing)
        }
    }
}

private struct OutputDeviceRow: View {
    let device: AudioOutputDevice
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isSelected ? Color.white : Color.white.opacity(0.14)))
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: IslandLayout.deviceRowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}
