import SwiftUI
import WidgetKit

struct CampusEntry: TimelineEntry {
    let date: Date
    let data: CampusData
    var error: Bool = false
}
struct CampusProvider: TimelineProvider {
    func placeholder(in context: Context) -> CampusEntry { CampusEntry(date: .now, data: CampusData()) }
    func getSnapshot(in context: Context, completion: @escaping (CampusEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CampusEntry>) -> Void) {
        let now = Date.now
        let current = entry()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        let next = min(now.addingTimeInterval(900), midnight)
        completion(Timeline(entries: [current], policy: .after(next)))
    }
    private func entry() -> CampusEntry {
        do { return CampusEntry(date: .now, data: try Storage.read()) }
        catch { return CampusEntry(date: .now, data: CampusData(), error: true) }
    }
}
struct CampusWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: CampusEntry
    private var courses: [Course] { entry.data.courses.filter { $0.occurs(on: entry.date) }.sorted { $0.start < $1.start } }
    private let green = Color(red: 0.22, green: 0.40, blue: 0.31)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("日程", systemImage: "square.grid.2x2.fill").font(.headline).foregroundStyle(green)
                Spacer()
                Text(entry.date, format: .dateTime.month().day().weekday()).font(.caption).foregroundStyle(.secondary)
            }
            if entry.error {
                Text("暂时无法读取数据").font(.headline)
                Text("请打开日程，检查共享数据配置。").font(.caption).foregroundStyle(.secondary)
            } else if family == .systemSmall {
                if let next = courses.first(where: { $0.end > Calendar.current.component(.hour, from: entry.date) * 60 + Calendar.current.component(.minute, from: entry.date) }) {
                    Text(next.title).font(.headline).lineLimit(2)
                    Text("\(clockText(next.start)) · \(next.location)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else { Text("接下来没有课程").font(.subheadline) }
                Spacer(minLength: 0)
                Text("\(entry.data.pending.count) 项待办").font(.caption).foregroundStyle(green)
                if let task = entry.data.pending.first { Text(task.title).font(.caption).lineLimit(1) }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("今日课程").font(.caption).foregroundStyle(.secondary)
                        if courses.isEmpty { Text("今天没有课程").font(.subheadline) }
                        ForEach(Array(courses.prefix(family == .systemLarge ? 5 : 2))) { course in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.title).font(.subheadline.bold()).lineLimit(1)
                                Text("\(clockText(course.start))–\(clockText(course.end)) \(course.location)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        if courses.count > (family == .systemLarge ? 5 : 2) { Text("另有 \(courses.count - (family == .systemLarge ? 5 : 2)) 门课").font(.caption2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("待办 · \(entry.data.pending.count)").font(.caption).foregroundStyle(.secondary)
                        if entry.data.pending.isEmpty { Text("全部完成，休息一下").font(.subheadline) }
                        ForEach(Array(entry.data.pending.prefix(family == .systemLarge ? 5 : 2))) { task in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(task.title, systemImage: "circle").font(.subheadline).lineLimit(1)
                                if let due = task.due { Text(due, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(due < entry.date ? .orange : .secondary) }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                if family == .systemLarge { Text("打开日程，管理课程与待办").font(.caption2).foregroundStyle(.secondary) }
            }
        }.containerBackground(for: .widget) { Color(red: 0.95, green: 0.96, blue: 0.93) }
    }
}
@main struct CampusWidget: Widget {
    let kind = "CampusDesk.Today"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CampusProvider()) { CampusWidgetView(entry: $0) }
            .configurationDisplayName("日程 · 今日安排")
            .description("查看今日课程与待办，点击打开应用管理。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
