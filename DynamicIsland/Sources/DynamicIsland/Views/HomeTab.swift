import AppKit
import SwiftUI

/// Apple Home scenes and accessories, as tiles that run the user's shortcuts.
struct HomeTab: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        if model.home.shortcuts.isEmpty {
            emptyState
        } else {
            tiles
        }
    }

    private var tiles: some View {
        let home = model.home
        let columns = IslandLayout.homeColumns
        let rows = stride(from: 0, to: home.shortcuts.count, by: columns).map {
            Array(home.shortcuts[$0..<min($0 + columns, home.shortcuts.count)])
        }
        let grid = VStack(spacing: IslandLayout.homeTileSpacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: IslandLayout.homeTileSpacing) {
                    ForEach(row) { shortcut in
                        HomeTile(shortcut: shortcut,
                                 state: home.runStates[shortcut.id] ?? .idle,
                                 isOn: home.toggleStates[shortcut.id]) {
                            home.run(shortcut)
                        }
                        .contextMenu {
                            Button("Edit in Shortcuts") { home.reveal(shortcut) }
                        }
                    }
                    ForEach(row.count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: IslandLayout.homeTileHeight)
            }
        }

        return Group {
            if rows.count > IslandLayout.maxHomeRows {
                IslandScroll { grid }
            } else {
                grid
            }
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        let home = model.home
        let folder = model.settings.homeFolderName
        return HStack(spacing: 16) {
            Group {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Home") {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "house.fill").font(.system(size: 26)).foregroundStyle(.orange)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(home.folderExists ? "The “\(folder)” folder is empty" : "Control your home from here")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Create shortcuts with Control Home in Shortcuts and put them in a folder named “\(folder)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    CapsuleButton(title: "Open Shortcuts") { HomeService.openShortcutsApp() }
                    CapsuleButton(title: "Open Home") { HomeService.openHomeApp() }
                }
                .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }
}

private struct HomeTile: View {
    let shortcut: HomeShortcut
    let state: HomeRunState
    let isOn: Bool?
    let action: () -> Void

    @State private var isHovering = false
    @State private var successCount = 0

    var body: some View {
        let isActive = isOn == true
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                icon(isActive: isActive)
                Spacer(minLength: 0)
                Text(shortcut.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let status {
                    Text(status)
                        .font(.system(size: 11))
                        .opacity(0.6)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .foregroundStyle(isActive ? Color.black : Color.white)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.94) : Color.white.opacity(isHovering ? 0.15 : 0.09))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableTileStyle())
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)
        .onChange(of: state) { _, newState in
            if newState == .succeeded { successCount += 1 }
        }
        .help(shortcut.name)
    }

    private var status: String? {
        switch state {
        case .running: "Running…"
        case .failed: "Failed"
        case .succeeded: isOn.map { $0 ? "On" : "Off" } ?? "Done"
        case .idle: isOn.map { $0 ? "On" : "Off" }
        }
    }

    @ViewBuilder
    private func icon(isActive: Bool) -> some View {
        ZStack {
            Circle().fill(isActive ? accent : Color.white.opacity(0.14))
            switch state {
            case .running:
                Spinner(color: isActive ? .black : .white)
                    .frame(width: 14, height: 14)
                    .transition(.scale.combined(with: .opacity))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .transition(.scale.combined(with: .opacity))
            default:
                Group {
                    if let emoji = shortcut.emoji {
                        Text(emoji).font(.system(size: 15))
                    } else {
                        Image(systemName: shortcut.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .symbolEffect(.bounce, value: successCount)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 28, height: 28)
    }

    private var accent: Color {
        switch shortcut.symbol {
        case "lightbulb.fill", "lamp.floor.fill", "lamp.desk.fill", "light.recessed.fill": .orange
        case "lock.fill", "door.garage.closed": .teal
        case "thermometer.medium": .red
        case "fan.fill", "air.purifier.fill": .cyan
        case "blinds.horizontal.closed", "moon.stars.fill": .indigo
        case "tv.fill", "hifispeaker.fill": .blue
        case "poweroutlet.type.f.fill": .green
        default: .orange
        }
    }
}

private struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct Spinner: View {
    var color: Color
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.82)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
    }
}

struct CapsuleButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(isHovering ? 0.22 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableTileStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
