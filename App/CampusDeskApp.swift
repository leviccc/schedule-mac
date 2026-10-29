import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WidgetKit

// Explicit alias avoids the newer SDK State macro when using Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@MainActor final class CampusStore: ObservableObject {
    @Published private(set) var data = CampusData()
    @Published var error: String?
    @Published var loaded = false
    init() {
        do { data = try Storage.read(); loaded = true }
        catch { self.error = "读取失败，已停止写入以保护原数据：\(error.localizedDescription)" }
    }
    @discardableResult func update(_ change: (inout CampusData) -> Void) -> Bool {
        guard loaded else { error = "请先解决数据读取问题后重新打开应用。"; return false }
        var next = data
        change(&next)
        do {
            try Storage.write(next)
            data = next
            #if !LOCAL_PREVIEW
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
}

@main struct CampusDeskApp: App {
    @StateObject private var store = CampusStore()
    var body: some Scene {
        WindowGroup("日程 · 课表与待办") {
            Dashboard().environmentObject(store).frame(minWidth: 940, minHeight: 640)
                .tint(Color(red: 0.22, green: 0.40, blue: 0.31))
                .alert("暂时无法完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }.defaultSize(width: 1150, height: 760)
    }
}

struct Dashboard: View {
    @EnvironmentObject var store: CampusStore
    @ViewState private var section = "概览"
    @ViewState private var showEditor = false
    @ViewState private var editCourse: Course?
    @ViewState private var editTodo: Todo?
    @ViewState private var editorKind = 0
    @ViewState private var pendingCourseDelete: Course?
    @ViewState private var pendingTodoDelete: Todo?
    @ViewState private var weekOffset = 0
    private let accent = Color(red: 0.22, green: 0.40, blue: 0.31)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Label("日程", systemImage: "square.grid.2x2.fill").font(.system(size: 25, weight: .bold)).foregroundStyle(accent)
                Text("课表与待办 · 0.3").font(.caption).foregroundStyle(.secondary)
                ForEach(["概览", "周课表", "全部待办"], id: \.self) { name in
                    Button { section = name } label: {
                        Label(name, systemImage: name == "概览" ? "sun.max" : name == "周课表" ? "calendar" : "checklist")
                            .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(section == name ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "macwindow.on.rectangle").font(.title2)
                    Text("桌面上的今日安排").font(.headline)
                    Text("安装签名版本后，在桌面右键 → 编辑小组件，搜索「日程」。").font(.caption).foregroundStyle(.secondary)
                    #if LOCAL_PREVIEW
                    Text("当前为管理应用预览版，尚未安装桌面小组件。").font(.caption).foregroundStyle(.orange)
                    #endif
                }.padding(14).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                Text("本地保存 · 随时编辑").font(.caption2).foregroundStyle(.secondary)
            }.padding(22).frame(width: 205).frame(maxHeight: .infinity).background(Color(red: 0.93, green: 0.94, blue: 0.91))
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section == "概览" ? "今天，从容开始。" : section).font(.system(size: 28, weight: .semibold))
                        Text(Date.now.formatted(.dateTime.year().month().day().weekday(.wide))).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("添加课程") { openEditor(kind: 0) }
                        Button("添加待办 / 作业") { openEditor(kind: 1) }
                    } label: { Label("新建", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if section == "周课表" { weekView }
                        else if section == "全部待办" { todoList(includeDone: true) }
                        else {
                            HStack(spacing: 14) {
                                metric("今日课程", value: todayCourses.count, icon: "books.vertical")
                                metric("待完成", value: store.data.pending.count, icon: "checkmark.circle")
                                metric("已逾期", value: store.data.pending.filter { ($0.due ?? .distantFuture) < .now }.count, icon: "clock")
                            }
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("今日课表").font(.title3.bold())
                                    if todayCourses.isEmpty { empty("今天没有课程", detail: "可切换周课表查看，或手动添加课程。", icon: "cup.and.saucer") }
                                    ForEach(todayCourses) { courseCard($0) }
                                }.frame(maxWidth: .infinity)
                                todoList(includeDone: false).frame(maxWidth: .infinity)
                            }
                        }
                    }.padding(.bottom, 20)
                }
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $showEditor) { ItemEditor(kind: editorKind, course: editCourse, todo: editTodo).environmentObject(store) }
        .alert("删除这条记录？", isPresented: Binding(get: { pendingCourseDelete != nil || pendingTodoDelete != nil }, set: { if !$0 { pendingCourseDelete = nil; pendingTodoDelete = nil } })) {
            Button("取消", role: .cancel) { pendingCourseDelete = nil; pendingTodoDelete = nil }
            Button("删除", role: .destructive) {
                let c = pendingCourseDelete?.id; let t = pendingTodoDelete?.id
                store.update { data in data.courses.removeAll { $0.id == c }; data.todos.removeAll { $0.id == t } }
                pendingCourseDelete = nil; pendingTodoDelete = nil
            }
        } message: { Text("删除后无法撤销。") }
    }
    private var todayCourses: [Course] { store.data.courses.filter { $0.occurs(on: .now) }.sorted { $0.start < $1.start } }
    private func metric(_ title: String, value: Int, icon: String) -> some View {
        HStack { VStack(alignment: .leading, spacing: 10) { Text(title).foregroundStyle(.secondary); Text("\(value)").font(.system(size: 32, weight: .semibold, design: .rounded)) }; Spacer(); Image(systemName: icon).font(.title).foregroundStyle(accent) }
            .padding(20).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func empty(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 12) { Image(systemName: icon).font(.largeTitle).foregroundStyle(accent); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity).padding(30).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private func courseCard(_ c: Course) -> some View {
        HStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(clockText(c.start)) – \(clockText(c.end))").font(.caption.monospacedDigit()).foregroundStyle(accent)
                Text(c.title).font(.headline)
                if !c.location.isEmpty { Label(c.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Menu {
                Button("编辑") { editCourse = c; editTodo = nil; editorKind = 0; showEditor = true }
                Button("删除", role: .destructive) { pendingCourseDelete = c }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(14).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private func todoList(includeDone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(includeDone ? "作业与其他待办" : "接下来要做").font(.title3.bold()); Spacer(); Button { openEditor(kind: 1) } label: { Image(systemName: "plus") }.buttonStyle(.plain) }
            let items = includeDone ? store.data.pending + store.data.todos.filter(\.done) : store.data.pending
            if items.isEmpty { empty("暂时没有待办", detail: "把作业和计划放在这里。", icon: "checkmark.seal") }
            ForEach(items) { task in
                HStack(alignment: .top, spacing: 10) {
                    Button { store.update { data in if let i = data.todos.firstIndex(where: { $0.id == task.id }) { data.todos[i].done.toggle() } } } label: { Image(systemName: task.done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(accent) }.buttonStyle(.plain).accessibilityLabel(task.done ? "标记为未完成" : "完成待办")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title).strikethrough(task.done).foregroundStyle(task.done ? .secondary : .primary)
                        if !task.course.isEmpty { Text(task.course).font(.caption).foregroundStyle(.secondary) }
                        if let due = task.due { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(due < .now && !task.done ? .orange : .secondary) }
                    }
                    Spacer()
                    Menu { Button("编辑") { editTodo = task; editCourse = nil; editorKind = 1; showEditor = true }; Button("删除", role: .destructive) { pendingTodoDelete = task } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var weekView: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset + weekOffset * 7, to: today)!
        return VStack(alignment: .leading, spacing: 16) {
            HStack { Button("上一周") { weekOffset -= 1 }; Button("本周") { weekOffset = 0 }; Button("下一周") { weekOffset += 1 }; Spacer(); Text("每周重复 · 按课程有效日期显示").font(.caption).foregroundStyle(.secondary) }
            WeekTimetable(monday: monday, courses: store.data.courses, onEdit: { course in
                editCourse = course; editTodo = nil; editorKind = 0; showEditor = true
            }, onDelete: { pendingCourseDelete = $0 })

        }
    }
    private func openEditor(kind: Int) { editCourse = nil; editTodo = nil; editorKind = kind; showEditor = true }

}

struct ItemEditor: View {
    @EnvironmentObject var store: CampusStore
    @Environment(\.dismiss) var dismiss
    @ViewState var kind: Int
    var course: Course?
    var todo: Todo?
    var initialTitle = ""
    @ViewState private var title = ""
    @ViewState private var location = ""
    @ViewState private var courseName = ""
    @ViewState private var weekday = 1
    @ViewState private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
    @ViewState private var end = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
    @ViewState private var from = Date.now
    @ViewState private var until = Calendar.current.date(byAdding: .month, value: 5, to: .now)!
    @ViewState private var hasDue = false
    @ViewState private var due = Date.now
    @ViewState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(course != nil || todo != nil ? "编辑记录" : "确认并添加").font(.title2.bold())
            if course == nil && todo == nil { Picker("类型", selection: $kind) { Text("课程").tag(0); Text("作业 / 待办").tag(1) }.pickerStyle(.segmented) }
            Form {
                TextField(kind == 0 ? "课程名称" : "待办内容", text: $title)
                if kind == 0 {
                    Picker("星期", selection: $weekday) { ForEach(1...7, id: \.self) { Text(weekdayNames[$0 - 1]).tag($0) } }
                    DatePicker("开始时间", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("结束时间", selection: $end, displayedComponents: .hourAndMinute)
                    TextField("上课地点", text: $location)
                    DatePicker("有效开始日期", selection: $from, displayedComponents: .date)
                    DatePicker("有效结束日期", selection: $until, displayedComponents: .date)
                    Text("每周重复一次。单双周、节次及临时调课暂需分开录入，请核对具体时间。").font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("关联课程（可留空）", text: $courseName)
                    Toggle("设置截止时间", isOn: $hasDue)
                    if hasDue { DatePicker("截止时间", selection: $due) }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 490)
        .onAppear {
            title = course?.title ?? todo?.title ?? initialTitle
            if let c = course {
                weekday = c.weekday; location = c.location; from = c.semesterStart; until = c.semesterEnd
                start = Calendar.current.date(bySettingHour: c.start / 60, minute: c.start % 60, second: 0, of: .now)!
                end = Calendar.current.date(bySettingHour: c.end / 60, minute: c.end % 60, second: 0, of: .now)!
            }
            if let t = todo { courseName = t.course; hasDue = t.due != nil; due = t.due ?? .now }
        }
    }
    private func minutes(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
    private func save() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if kind == 0 {
            guard minutes(end) > minutes(start) else { error = "结束时间必须晚于开始时间。"; return }
            guard Calendar.current.startOfDay(for: until) >= Calendar.current.startOfDay(for: from) else { error = "有效结束日期不能早于开始日期。"; return }
            let new = Course(id: course?.id ?? UUID(), title: clean, weekday: weekday, start: minutes(start), end: minutes(end), location: location, semesterStart: from, semesterEnd: until)
            if store.update({ data in
                if let i = data.courses.firstIndex(where: { $0.id == new.id }) { data.courses[i] = new } else { data.courses.append(new) }
            }) { dismiss() } else { error = store.error }
        } else {
            let new = Todo(id: todo?.id ?? UUID(), title: clean, course: courseName, due: hasDue ? due : nil, done: todo?.done ?? false)
            if store.update({ data in
                if let i = data.todos.firstIndex(where: { $0.id == new.id }) { data.todos[i] = new } else { data.todos.append(new) }
            }) { dismiss() } else { error = store.error }
        }
    }
}

struct WeekTimetable: View {
    let monday: Date
    let courses: [Course]
    let onEdit: (Course) -> Void
    let onDelete: (Course) -> Void
    private let rowHeight: CGFloat = 68
    private let headerHeight: CGFloat = 48
    private let border = Color(red: 0.80, green: 0.85, blue: 0.92)
    private let header = Color(red: 0.91, green: 0.94, blue: 0.98)
    private func periods(on date: Date) -> [(Int, Int)] {
        let summer = (5...9).contains(Calendar.current.component(.month, from: date))
        let shift = summer ? 30 : 0
        return [(480,530),(540,590),(610,660),(670,720),
                (840+shift,890+shift),(900+shift,950+shift),
                (970+shift,1020+shift),(1030+shift,1080+shift),
                (1150+shift,1200+shift),(1210+shift,1260+shift)]
    }
    private func span(_ course: Course, on date: Date) -> ClosedRange<Int>? {
        let slots = periods(on: date)
        let touched = slots.indices.filter { course.start < slots[$0].1 && course.end > slots[$0].0 }
        guard let first = touched.first, let last = touched.last else { return nil }
        return first...last
    }
    private func cell(_ text: String, width: CGFloat, height: CGFloat, fill: Color) -> some View {
        Text(text).font(.caption).multilineTextAlignment(.center)
            .frame(width: width, height: height).background(fill)
            .overlay(Rectangle().stroke(border, lineWidth: 0.5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let columnWidth = max(100, (geometry.size.width - 70) / 7)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            cell("节次/星期", width: 70, height: headerHeight, fill: header)
                            HStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    cell("上\n午", width: 28, height: rowHeight * 4, fill: header)
                                    cell("下\n午", width: 28, height: rowHeight * 4, fill: header)
                                    cell("晚\n上", width: 28, height: rowHeight * 2, fill: header)
                                }
                                VStack(spacing: 0) { ForEach(1...10, id: \.self) { cell("\($0)", width: 42, height: rowHeight, fill: header) } }
                            }
                        }
                        ForEach(0..<7) { index in
                            let date = Calendar.current.date(byAdding: .day, value: index, to: monday)!
                            dayColumn(date, index: index, width: columnWidth)
                        }
                    }.padding(1)
                }
            }.frame(height: headerHeight + rowHeight * 10 + 18)
            Text("按所选周显示 · 空白格表示没有课程 · 点击课程编辑，右键可删除").font(.caption).foregroundStyle(.secondary)
            // Keep manually entered courses outside the school's periods accessible.
            ForEach(0..<7) { index in
                let date = Calendar.current.date(byAdding: .day, value: index, to: monday)!
                ForEach(courses.filter { $0.occurs(on: date) && span($0, on: date) == nil }) { course in
                    Button { onEdit(course) } label: { Text("节次外 · \(weekdayNames[index]) \(clockText(course.start))–\(clockText(course.end))  \(course.title)") }
                        .contextMenu { Button("删除", role: .destructive) { onDelete(course) } }
                }
            }
        }
    }
    private func dayColumn(_ date: Date, index: Int, width: CGFloat) -> some View {
        let items = courses.filter { $0.occurs(on: date) && span($0, on: date) != nil }.sorted { $0.start < $1.start }
        // Greedy lanes keep simultaneous courses visible instead of covering each other.
        var ends: [Int] = []
        var lanes: [UUID: Int] = [:]
        for course in items {
            let range = span(course, on: date)!
            let lane = ends.firstIndex(where: { $0 < range.lowerBound }) ?? ends.count
            if lane == ends.count { ends.append(range.upperBound) } else { ends[lane] = range.upperBound }
            lanes[course.id] = lane
        }
        let laneCount = max(1, ends.count)
        return VStack(spacing: 0) {
            cell("\(weekdayNames[index])\n\(date.formatted(.dateTime.month().day()))", width: width, height: headerHeight, fill: header)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<10) { _ in cell("", width: width, height: rowHeight, fill: Color(nsColor: .textBackgroundColor)) }
                }
                ForEach(items) { course in
                    let range = span(course, on: date)!
                    let cardWidth = width / CGFloat(laneCount)
                    Button { onEdit(course) } label: {
                        VStack(spacing: 5) {
                            Text(course.title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            Text("\(clockText(course.start))–\(clockText(course.end))").font(.system(size: 10).monospacedDigit())
                            if !course.location.isEmpty { Text(course.location).font(.system(size: 11)) }
                        }.multilineTextAlignment(.center).padding(5)
                            .frame(width: max(1, cardWidth - 6), height: CGFloat(range.count) * rowHeight - 6)
                            .background(Color.accentColor.opacity(0.08))
                            .overlay(Rectangle().stroke(border, lineWidth: 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .help("\(course.title) · \(clockText(course.start))–\(clockText(course.end)) · \(course.location)")
                        .contextMenu { Button("编辑课程") { onEdit(course) }; Button("删除课程", role: .destructive) { onDelete(course) } }
                        .offset(x: CGFloat(lanes[course.id] ?? 0) * cardWidth + 3, y: CGFloat(range.lowerBound) * rowHeight + 3)
                }
            }.frame(width: width, height: rowHeight * 10)
        }
    }
}
