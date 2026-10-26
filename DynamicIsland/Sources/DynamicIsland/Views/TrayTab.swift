import AppKit
import SwiftUI

/// A shelf in the notch: drop files, images or links here and drag them out somewhere else later.
struct TrayTab: View {
    @Environment(IslandModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        let tray = model.tray
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tray.items.isEmpty ? "Tray" : (tray.items.count == 1 ? "1 objekt" : "\(tray.items.count) objekt"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                if tray.isImporting { ProgressView().controlSize(.mini) }
                Spacer()
                Button { tray.openFolder() } label: {
                    Image(systemName: "folder").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 24))
                .help("Öppna trayens mapp")
                Button { tray.clear() } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 24))
                .help("Flytta allt i trayen till papperskorgen")
                .disabled(tray.items.isEmpty)
            }
            .frame(height: 24)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isTargeted ? 0.1 : (tray.items.isEmpty ? 0.04 : 0)))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(isTargeted ? 0.7 : (tray.items.isEmpty ? 0.22 : 0)),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                if tray.items.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 22, weight: .medium))
                            .symbolEffect(.bounce, value: isTargeted)
                        Text(isTargeted ? "Släpp för att spara här" : "Släpp filer, bilder eller länkar här")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Dra ut dem igen där du behöver dem")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                } else {
                    IslandScroll(axis: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(tray.items) { item in TrayTile(item: item) }
                        }
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(height: 106)
            .animation(.easeOut(duration: 0.15), value: isTargeted)
            .onDrop(of: TrayService.acceptedTypes, isTargeted: $isTargeted) { providers in
                tray.add(providers)
            }
        }
        .padding(.top, 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tray.items)
    }
}

private struct TrayTile: View {
    let item: TrayItem
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        let tray = model.tray
        VStack(spacing: 5) {
            Group {
                if let image = tray.thumbnails[item.id] {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: item.isImage ? .fill : .fit)
                } else {
                    Image(systemName: "doc").font(.system(size: 26)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: item.isImage ? 10 : 0, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 74)
        }
        .padding(.vertical, 6)
        .frame(width: 82)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(isHovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { tray.remove(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 18))
                .background(Circle().fill(Color(white: 0.25)))
                .offset(x: 2, y: -2)
                .help("Ta bort från trayen")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { tray.open(item) }
        .contextMenu {
            Button("Öppna") { tray.open(item) }
            Button("Visa i Finder") { tray.reveal(item) }
            Button("Kopiera") { tray.copyToPasteboard(item) }
            Divider()
            Button("Ta bort från trayen") { tray.remove(item) }
        }
        .help("\(item.url.lastPathComponent) – dra ut den eller dubbelklicka för att öppna")
    }
}
