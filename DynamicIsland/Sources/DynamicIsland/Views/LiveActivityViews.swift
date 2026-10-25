import SwiftUI

/// Artwork to the left of the notch, equalizer to the right.
struct CompactMediaView: View {
    let namespace: Namespace.ID
    @Environment(IslandModel.self) private var model

    var body: some View {
        let notch = model.notch
        let artSize = notch.height - 10
        let inset = (notch.height - artSize) / 2

        HStack(spacing: 0) {
            ArtworkView(image: model.media.artwork, version: model.media.artworkVersion, size: artSize, cornerRadius: 6)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .padding(.leading, inset + 1)
            Spacer(minLength: 0)
            EqualizerView(color: model.media.accentColor, isPlaying: model.media.isPlaying, height: 12)
                .padding(.trailing, inset + 3)
        }
        .padding(.horizontal, model.earRadius)
        .frame(height: notch.height)
    }
}

/// Shown for a few seconds when the song changes.
struct PeekView: View {
    let namespace: Namespace.ID
    @Environment(IslandModel.self) private var model

    var body: some View {
        let media = model.media
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            HStack(spacing: 11) {
                ArtworkView(image: media.artwork, version: media.artworkVersion, size: 38, cornerRadius: 9)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: media.title, font: .system(size: 13, weight: .semibold))
                    MarqueeText(text: media.subtitle, font: .system(size: 12), color: .white.opacity(0.55))
                }
                EqualizerView(color: media.accentColor, isPlaying: media.isPlaying, height: 14)
            }
            .padding(.horizontal, 14)
            .padding(.top, 1)
        }
        .padding(.horizontal, model.earRadius)
    }
}

struct HUDView: View {
    let kind: HUDKind
    @Environment(IslandModel.self) private var model

    var body: some View {
        switch kind {
        case .volume, .brightness: levelHUD
        case .outputDevice: OutputDeviceHUD()
        }
    }

    private var levelHUD: some View {
        let audio = model.audio
        let isVolume = kind == .volume
        let level = isVolume ? (audio.isMuted ? 0 : audio.volume) : model.brightness.brightness
        let symbol: String = if isVolume {
            audio.isMuted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        } else {
            level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }

        return HStack(spacing: 0) {
            Image(systemName: symbol, variableValue: isVolume ? level : nil)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: model.hudSideWidth)
            Spacer(minLength: 0)
            LevelBar(level: level, dimmed: isVolume && audio.isMuted)
                .frame(width: model.hudSideWidth - 24, height: 5)
                .frame(width: model.hudSideWidth)
        }
        .padding(.horizontal, model.earRadius)
        .frame(height: model.notch.height)
    }
}

private struct LevelBar: View {
    var level: Double
    var dimmed: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white.opacity(dimmed ? 0.4 : 1))
                    .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: level)
    }
}

private struct OutputDeviceHUD: View {
    @Environment(IslandModel.self) private var model
    @State private var bounce = false

    var body: some View {
        let device = model.audio.currentDevice
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            HStack(spacing: 11) {
                Image(systemName: device?.symbolName ?? "speaker.wave.2.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: bounce)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device?.name ?? "Audio output")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device?.isWireless == true ? "Connected" : "Audio output")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white, .green)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        .padding(.horizontal, model.earRadius)
        .onAppear { bounce.toggle() }
    }
}
