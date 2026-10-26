import AppKit
import SwiftUI

/// Three days side by side with an hour grid, styled after the Hub's calendar: day names over
/// big dates, an all-day row, solid coloured events with the title over the time, and a red line
/// at the current time. Click an event to open it, click an empty slot to book one.
struct CalendarGridView: View {
    @Environment(IslandModel.self) private var model

    static let hourHeight: CGFloat = 38
    private let gutter: CGFloat = 36

    var body: some View {
        let hub = model.hub
        VStack(spacing: 0) {
            if let event = hub.selectedEvent {
                CalendarEventDetail(event: event)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                header
                dayHeaders
                allDayRow
                grid
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: hub.selectedEventID)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: hub.calendarStart)
    }

    // MARK: Header

    private var header: some View {
        let hub = model.hub
        let days = hub.calendarDays
        return HStack(spacing: 6) {
            Button { hub.moveCalendar(by: -1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Föregående dag")
            Button { hub.showToday() } label: {
                Text("Idag")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Button { hub.moveCalendar(by: 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Nästa dag")
            Text(rangeTitle(days))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 4)
            if let week = days.first.map({ Calendar(identifier: .iso8601).component(.weekOfYear, from: $0) }) {
                Text("v. \(week)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(Capsule().fill(.white.opacity(0.08)))
            }
            Spacer(minLength: 4)
            if case .notConnected = hub.calendarConnection {
                CapsuleButton(title: "Koppla Google") { hub.connectCalendar() }
            }
            Button { model.onEditMeeting?(nil, defaultStart()) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Ny händelse")
            Button { hub.openWeb(.calendar) } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(IslandButtonStyle(diameter: 24))
            .help("Öppna kalendern i Acord Hub")
        }
        .frame(height: 28)
    }

    private func rangeTitle(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
        let start = first.formatted(.dateTime.day().locale(Self.swedish))
        let end = last.formatted(.dateTime.day().month(.abbreviated).locale(Self.swedish))
        return sameMonth ? "\(start) – \(end)" : "\(first.formatted(.dateTime.day().month(.abbreviated).locale(Self.swedish))) – \(end)"
    }

    static let swedish = Locale(identifier: "sv_SE")

    private func defaultStart() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let day = model.hub.calendarStart
        let base = calendar.isDateInToday(day) ? now : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let minute = calendar.component(.minute, from: base)
        return calendar.date(byAdding: .minute, value: (30 - minute % 30) % 30, to: base) ?? base
    }

    // MARK: Days

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(model.hub.calendarDays, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 0) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Self.swedish)).uppercased()
                        .replacingOccurrences(of: ".", with: ""))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? Color.black : Color.white)
                        .frame(width: 28, height: 24)
                        .background(Circle().fill(isToday ? Color.white : Color.clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
        .frame(height: 46)
    }

    @ViewBuilder
    private var allDayRow: some View {
        let hub = model.hub
        let days = hub.calendarDays
        let allDay = days.map { day in hub.calendarEvents(on: day).filter(\.isAllDay) }
        if allDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("Heldag")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: gutter, alignment: .leading)
                ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                    VStack(spacing: 2) {
                        ForEach(allDay[index].prefix(2)) { event in
                            Button { hub.select(event: event) } label: {
                                Text(event.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CalendarColors.fill(event)))
                            }
                            .buttonStyle(.plain)
                            .help(event.title)
                        }
                        if allDay[index].count > 2 {
                            Text("+\(allDay[index].count - 2) till")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: Grid

    private var grid: some View {
        let hub = model.hub
        let days = hub.calendarDays
        return GeometryReader { geometry in
            let columnWidth = (geometry.size.width - gutter) / CGFloat(max(days.count, 1))
            IslandScroll(initialOffset: max(CGFloat(Calendar.current.component(.hour, from: Date()) - 1), 0) * Self.hourHeight) {
                ZStack(alignment: .topLeading) {
                    hourLines(width: geometry.size.width)
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        DayColumn(day: day, width: columnWidth)
                            .offset(x: gutter + CGFloat(index) * columnWidth)
                    }
                    nowLine(days: days, columnWidth: columnWidth)
                }
                .frame(width: geometry.size.width, height: Self.hourHeight * 24 + 8, alignment: .topLeading)
            }
        }
    }

    private func hourLines(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 4) {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: gutter - 4, alignment: .leading)
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                }
                .offset(y: CGFloat(hour) * Self.hourHeight - 5)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    @ViewBuilder
    private func nowLine(days: [Date], columnWidth: CGFloat) -> some View {
        if let index = days.firstIndex(where: { Calendar.current.isDateInToday($0) }) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let minutes = CGFloat(Calendar.current.component(.hour, from: context.date) * 60
                                      + Calendar.current.component(.minute, from: context.date))
                HStack(spacing: 0) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Rectangle().fill(Color.red).frame(height: 1.5)
                }
                .frame(width: columnWidth + 3)
                .offset(x: gutter + CGFloat(index) * columnWidth - 3, y: minutes / 60 * Self.hourHeight - 3.5)
                .allowsHitTesting(false)
            }
        }
    }
}

/// One day's timed events, laid out side by side where they overlap; click empty space to book.
private struct DayColumn: View {
    let day: Date
    let width: CGFloat
    @Environment(IslandModel.self) private var model

    var body: some View {
        let events = model.hub.calendarEvents(on: day).filter { !$0.isAllDay }
        let placed = Self.layout(events, day: day)
        ZStack(alignment: .topLeading) {
            // Click an empty slot to book it, on the half hour.
            Color.white.opacity(0.0001)
                .frame(width: width, height: CalendarGridView.hourHeight * 24)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    let minutes = Int(value.location.y / CalendarGridView.hourHeight * 60) / 30 * 30
                    let start = Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: day)) ?? day
                    model.onEditMeeting?(nil, start)
                })
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1, height: CalendarGridView.hourHeight * 24)
            ForEach(placed, id: \.event.id) { item in
                CalendarBlock(event: item.event, height: item.height)
                    .frame(width: max(width / CGFloat(item.columns) - 3, 10), height: max(item.height, 16))
                    .offset(x: 2 + CGFloat(item.column) * width / CGFloat(item.columns), y: item.y)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    struct Placed {
        let event: HubEvent
        let y: CGFloat
        let height: CGFloat
        var column: Int
        var columns: Int
    }

    /// Greedy columns within each group of overlapping events, like most calendars.
    static func layout(_ events: [HubEvent], day: Date) -> [Placed] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        var result: [Placed] = []
        var group: [Placed] = []
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast

        func closeGroup() {
            let count = max(columnEnds.count, 1)
            result += group.map { var item = $0; item.columns = count; return item }
            group = []
            columnEnds = []
        }

        for event in events.sorted(by: { $0.start < $1.start }) {
            let start = max(event.start, dayStart)
            let end = min(event.endDate, dayEnd)
            if start >= groupEnd { closeGroup() }
            let column = columnEnds.firstIndex { $0 <= start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(end) } else { columnEnds[column] = end }
            groupEnd = max(groupEnd, end)
            let y = CGFloat(start.timeIntervalSince(dayStart) / 3600) * CalendarGridView.hourHeight
            let height = CGFloat(end.timeIntervalSince(start) / 3600) * CalendarGridView.hourHeight - 2
            group.append(Placed(event: event, y: y, height: height, column: column, columns: 1))
        }
        closeGroup()
        return result
    }
}

/// An event as a solid coloured block: title in bold, the time under it when there's room.
private struct CalendarBlock: View {
    let event: HubEvent
    let height: CGFloat
    @Environment(IslandModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        let isPast = event.endDate < model.hub.now
        Button { model.hub.select(event: event) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if event.meetLink != nil {
                        Image(systemName: "video.fill").font(.system(size: 7.5, weight: .bold))
                    }
                    Text(event.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(height > 40 ? 2 : 1)
                }
                if height > 28 {
                    Text(timeRange)
                        .font(.system(size: 9.5).monospacedDigit())
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(CalendarColors.fill(event).opacity(isPast ? 0.55 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering ? 0.6 : 0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(event.title)\n\(timeRange)")
        .contextMenu {
            Button("Öppna") { model.hub.select(event: event) }
            if let meet = event.meetLink { Button("Gå med i mötet") { NSWorkspace.shared.open(meet) } }
            if event.googleID != nil {
                Button("Redigera…") { model.onEditMeeting?(event, nil) }
                Divider()
                Button("Ta bort…") { model.hub.deleteMeeting(event) }
            }
        }
    }

    private var timeRange: String {
        let format = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
        return "\(event.start.formatted(format)) – \(event.endDate.formatted(format))"
    }
}

/// The colours of the Hub's calendar: the Google calendar's own colour when there is one.
enum CalendarColors {
    private static let palette: [Color] = [
        Color(red: 0.93, green: 0.48, blue: 0.27), Color(red: 0.49, green: 0.74, blue: 0.33),
        Color(red: 0.42, green: 0.6, blue: 0.82), Color(red: 0.7, green: 0.45, blue: 0.86),
        Color(red: 0.88, green: 0.72, blue: 0.3),
    ]

    static func fill(_ event: HubEvent) -> Color {
        if let hex = event.colorHex, let color = Color(hex: hex) { return color.saturated() }
        if !event.isMeeting { return Color(red: 0.42, green: 0.6, blue: 0.82) }
        let sum = (event.calendarID ?? event.title).unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }

    /// Google's calendar colours are pale; the Hub shows them richer, and so does the island.
    func saturated() -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.25, 0.85), brightness: min(max(brightness * 0.92, 0.55), 0.9))
    }
}

/// An event opened in the island: when, where, who, and what you can do with it.
struct CalendarEventDetail: View {
    let event: HubEvent
    @Environment(IslandModel.self) private var model

    var body: some View {
        let hub = model.hub
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { hub.select(event: nil) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 24))
                .help("Tillbaka till kalendern")
                RoundedRectangle(cornerRadius: 3).fill(CalendarColors.fill(event)).frame(width: 4, height: 18)
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                row("clock", when)
                if let location = event.location, !location.isEmpty { row("mappin.and.ellipse", location) }
                if event.attendeeCount > 0 { row("person.2", "\(event.attendeeCount) deltagare") }
                if let client = event.clientName { row("building.2", client) }
                if let detail = event.detail, !detail.isEmpty {
                    IslandScroll {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 90)
                }
            }
            HStack(spacing: 6) {
                if let meet = event.meetLink {
                    actionButton("Gå med", "video.fill", tint: .green, filled: true) { NSWorkspace.shared.open(meet) }
                }
                if let web = event.webLink {
                    actionButton("Google Kalender", "arrow.up.right", tint: .white) { NSWorkspace.shared.open(web) }
                } else {
                    actionButton("Öppna i Hubben", "arrow.up.right", tint: .white) { hub.openWeb(.calendar) }
                }
                if event.googleID != nil {
                    actionButton("Redigera", "pencil", tint: .white) { model.onEditMeeting?(event, nil) }
                    actionButton("Ta bort", "trash", tint: Color(red: 1, green: 0.45, blue: 0.42)) { hub.deleteMeeting(event) }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var when: String {
        let swedish = CalendarGridView.swedish
        let day = event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(swedish))
        guard !event.isAllDay else { return day.capitalized + " · heldag" }
        let time = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
        return day.capitalized + " · \(event.start.formatted(time))–\(event.endDate.formatted(time))"
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
        }
    }

    private func actionButton(_ title: String, _ symbol: String, tint: Color, filled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(filled ? Color.black : tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(filled ? tint : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
