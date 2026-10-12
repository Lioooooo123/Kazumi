// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI
import KazumiCore

struct SeasonCalendarView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 560), spacing: 12)]

    var body: some View {
        let weekday = min(max(model.selectedWeekday, 1), 7)
        let items = model.timeline.indices.contains(weekday - 1) ? model.timeline[weekday - 1] : []
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weekdayPicker
                if let error = model.timelineError, model.timeline.allSatisfy(\.isEmpty) {
                    EmptyHint(title: "时间表不可用", message: error, systemImage: "calendar.badge.exclamationmark")
                    Button("重试") { Task { await model.loadTimeline() } }
                } else if items.isEmpty, !model.timelineLoading {
                    EmptyHint(title: "这一天没有番剧", message: "换一天，或切换放送季度。", systemImage: "calendar")
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { subject in
                            Button {
                                model.open(subject)
                            } label: {
                                TimelineCard(subject: subject, showRating: model.settings.showRating)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                LoadingBar(active: model.timelineLoading)
            }
            .padding(20)
            .frame(maxWidth: 1280, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(seasonTitle)
        .toolbar { seasonMenu }
        .task { if model.timeline.allSatisfy(\.isEmpty) { await model.loadTimeline() } }
    }

    private var seasonTitle: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: model.seasonAnchor)
        return AnimeCalendar.seasonLabel(year: parts.year ?? 2024, month: parts.month ?? 1)
    }

    private var weekdayPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                let count = model.timeline.indices.contains(day - 1) ? model.timeline[day - 1].count : 0
                let selected = model.selectedWeekday == day
                Button {
                    model.selectedWeekday = day
                } label: {
                    VStack(spacing: 2) {
                        Text(AnimeCalendar.weekdayNames[day - 1])
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        Text(count == 0 ? " " : "\(count)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ToolbarContentBuilder
    private var seasonMenu: some ToolbarContent {
        ToolbarItem {
            Menu {
                let year = Calendar.current.component(.year, from: Date())
                ForEach((year - 6)...year, id: \.self) { year in
                    Menu("\(year)") {
                        ForEach([1, 4, 7, 10], id: \.self) { month in
                            let date = seasonDate(year: year, month: month)
                            Button(AnimeCalendar.seasonName(month: month) + "季") {
                                guard date <= Date() else { return }
                                model.seasonAnchor = date
                                Task { await model.loadTimeline() }
                            }
                            .disabled(date > Date())
                        }
                    }
                }
            } label: {
                Label("季度", systemImage: "calendar")
            }
        }
        ToolbarItem {
            Button {
                Task { await model.loadTimeline() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private func seasonDate(year: Int, month: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = 1
        return Calendar.current.date(from: parts) ?? Date()
    }
}
