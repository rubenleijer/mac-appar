import SwiftUI

/// A notification from Acord Hub dropping out of the notch.
struct HubAlertView: View {
    @Environment(IslandModel.self) private var model
    @State private var bounce = false

    var body: some View {
        let hub = model.hub
        let alert = hub.latestAlert
        let kind = alert?.kind ?? .newTask
        let more = hub.latestAlertBatch - 1
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white, kind.color)
                    .symbolEffect(.bounce, value: bounce)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(alert?.title ?? "Acord Hub")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text((alert?.detail ?? "") + (more > 0 ? " · +\(more) more" : ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Hub")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.14)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .padding(.horizontal, model.earRadius)
        .onAppear { bounce = true }
    }
}

/// Next to the notch: what's coming up on the left, how long until it on the right.
struct CompactHubView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let item = model.hub.liveItem
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: symbol(item?.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color(item?.kind))
                Text(label(item))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(width: model.hudSideWidth)
            .help(item?.title ?? "")
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(trailing(item, now: context.date))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color(item?.kind))
                    .contentTransition(.numericText())
            }
            .frame(width: model.hudSideWidth)
        }
        .padding(.horizontal, model.earRadius)
        .frame(height: model.notch.height)
    }

    private func symbol(_ kind: HubLiveItem.Kind?) -> String {
        switch kind {
        case .event, .none: "calendar"
        case .ongoingEvent: "person.2.fill"
        case .post: "paperplane.fill"
        case .overdue: "exclamationmark.circle.fill"
        }
    }

    private func color(_ kind: HubLiveItem.Kind?) -> Color {
        switch kind {
        case .event, .none: .orange
        case .ongoingEvent: .green
        case .post: .pink
        case .overdue: Color(red: 1, green: 0.36, blue: 0.34)
        }
    }

    private func label(_ item: HubLiveItem?) -> String {
        switch item?.kind {
        case .ongoingEvent: "Now"
        case .post: "Post"
        case .overdue: "Late"
        default: "Next"
        }
    }

    private func trailing(_ item: HubLiveItem?, now: Date) -> String {
        guard let item else { return "" }
        switch item.kind {
        case .overdue:
            return "\(item.count)"
        case .ongoingEvent:
            guard let end = item.date else { return "Now" }
            return shortDuration(end.timeIntervalSince(now))
        case .event, .post:
            guard let date = item.date else { return "" }
            return date <= now ? "Now" : shortDuration(date.timeIntervalSince(now))
        }
    }
}
