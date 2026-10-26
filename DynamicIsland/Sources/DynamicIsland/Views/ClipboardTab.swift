import AppKit
import SwiftUI

/// The clipboard queue: everything copied, in the order it was copied. Click an item to put it on
/// the clipboard; with Queue on, each ⌘V moves the clipboard on to the next item down.
struct ClipboardTab: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let clipboard = model.clipboard
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            if clipboard.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 22, weight: .medium))
                    Text("Copy something – it lines up here")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Click an item to put it back on the clipboard.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                IslandScroll(followsEnd: true) {
                    VStack(spacing: 4) {
                        ForEach(Array(clipboard.queue.enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item, number: index + 1,
                                    isCurrent: item.id == clipboard.currentID,
                                    isNext: clipboard.queueMode && item.id == clipboard.nextItem?.id)
                        }
                    }
                    .padding(.bottom, 10)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.94),
                                             .init(color: .black.opacity(0.2), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(.top, 2)
        .frame(height: IslandLayout.clipboardContentHeight - 14, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: clipboard.items)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: clipboard.currentID)
    }

    private var toolbar: some View {
        @Bindable var clipboard = model.clipboard
        return HStack(spacing: 8) {
            Text(clipboard.items.count == 1 ? "1 item" : "\(clipboard.items.count) items")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 4)
            if clipboard.queueMode && !MediaKeyInterceptor.hasPermission {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help("⌘V can only move the queue on with Accessibility access – turn it on in System Settings → Privacy & Security → Accessibility. Clicking items still works.")
            }
            QueueToggle(isOn: $clipboard.queueMode)
            Button { clipboard.advance() } label: {
                Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Put the next item on the clipboard")
            .disabled(clipboard.nextItem == nil)
            Button { clipboard.clear() } label: {
                Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Clear the queue")
            .disabled(clipboard.items.isEmpty)
        }
        .frame(height: 26)
    }
}

private struct QueueToggle: View {
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "list.number" : "list.bullet").font(.system(size: 10, weight: .bold))
                Text(isOn ? "Queue on" : "Queue").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(isOn ? Color.white.opacity(0.92) : Color.white.opacity(isHovering ? 0.16 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isOn ? "Each ⌘V moves the clipboard on to the next item" : "Paste the queue in order: each ⌘V moves on to the next item")
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let number: Int
    let isCurrent: Bool
    let isNext: Bool
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isCurrent ? Color.green : Color.white.opacity(0.1))
                if item.kind == .image, let image = item.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.black : Color.white.opacity(0.7))
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .medium, design: item.kind == .text && looksLikeCode ? .monospaced : .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Image(systemName: item.symbol).font(.system(size: 9, weight: .semibold))
                    Text(subtitle)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(isCurrent ? Color.green : (isNext ? Color.orange : Color.white.opacity(0.45)))
                .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button { model.clipboard.remove(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 20))
                .help("Remove from the queue")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(isCurrent ? 0.12 : (isHovering ? 0.08 : 0.04)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isCurrent ? Color.green.opacity(0.7) : (isNext ? Color.orange.opacity(0.6) : .clear), lineWidth: 1.2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onTapGesture { model.clipboard.use(item) }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu {
            Button("Copy") { model.clipboard.use(item) }
            Button("Remove") { model.clipboard.remove(item) }
            Divider()
            Button("Clear Queue") { model.clipboard.clear() }
        }
        .help(item.text ?? item.preview)
    }

    private var subtitle: String {
        var parts: [String] = []
        if isCurrent { parts.append("On the clipboard") } else if isNext { parts.append("Next") }
        if let source = item.sourceApp { parts.append(source) }
        parts.append(item.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        return parts.joined(separator: " · ")
    }

    private var looksLikeCode: Bool {
        guard let text = item.text else { return false }
        return text.contains("{") || text.contains(";") || text.contains("=>") || text.hasPrefix("$ ")
    }
}
