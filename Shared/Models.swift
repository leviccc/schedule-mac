import Foundation

struct Course: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var weekday: Int // Monday = 1
    var start: Int // Minutes after midnight
    var end: Int
    var location: String
    var semesterStart: Date
    var semesterEnd: Date

    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return (calendar.component(.weekday, from: date) + 5) % 7 + 1 == weekday
            && day >= calendar.startOfDay(for: semesterStart)
            && day <= calendar.startOfDay(for: semesterEnd)
    }
}

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var course: String
    var due: Date?
    var done = false
}

struct CampusData: Codable, Equatable {
    var courses: [Course] = []
    var todos: [Todo] = []
    var pending: [Todo] {
        todos.filter { !$0.done }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }
}

enum Storage {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "CampusAppGroup") as? String ?? "group.local.schedule.sample"
    }
    static func url() throws -> URL {
        let fm = FileManager.default
        let base: URL
        #if LOCAL_PREVIEW
        base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ScheduleExample", isDirectory: true)
        #else
        guard let shared = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw NSError(domain: "CampusDesk", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问共享数据目录，请检查应用和小组件的 App Group 与签名配置。"])
        }
        base = shared
        #endif
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("campus-data.json")
    }
    static func read() throws -> CampusData {
        let path = try url()
        guard FileManager.default.fileExists(atPath: path.path) else {
            guard let seed = Bundle.main.url(forResource: "InitialSchedule", withExtension: "json") else { return CampusData() }
            let data = try JSONDecoder().decode(CampusData.self, from: Data(contentsOf: seed))
            try write(data)
            return data
        }
        return try JSONDecoder().decode(CampusData.self, from: Data(contentsOf: path))
    }
    static func write(_ data: CampusData) throws {
        try JSONEncoder().encode(data).write(to: url(), options: .atomic)
    }
}

func clockText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

struct ScheduleImport: Codable {
    var version: Int
    var term: String
    var campus: String
    var firstMonday: String?
    var timeBlocks: [String: ImportTime]?
    var seasonalTimeBlocks: SeasonalTimes?
    var courses: [ImportCourse]
    var todos: [ImportTodo]
    func resolved(monday: String, blocks: [String: ImportTime]) throws -> CampusData {
        func invalid(_ message: String) -> Error { NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        guard version == 1 else { throw invalid("不支持此 JSON 版本。") }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let format = DateFormatter(); format.calendar = cal; format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        let dateInput = courses.isEmpty ? "2026-01-05" : monday
        guard let first = format.date(from: dateInput), format.string(from: first) == dateInput, cal.component(.weekday, from: first) == 2 else { throw invalid("请填写第 1 周周一的日期，格式为 yyyy-MM-dd。") }
        func minute(_ value: String) throws -> Int {
            let p = value.split(separator: ":")
            guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...23).contains(h), (0...59).contains(m) else { throw invalid("时间请使用 HH:mm 格式。") }
            return h * 60 + m
        }
        var result = CampusData()
        for c in courses {
            guard !c.title.trimmingCharacters(in: .whitespaces).isEmpty, (1...7).contains(c.weekday), c.weekStart > 0, c.weekEnd >= c.weekStart, c.weekEnd <= 60, c.periodStart > 0, c.periodEnd >= c.periodStart else { throw invalid("课程字段无效：\(c.title)") }
            let key = "\(c.periodStart)-\(c.periodEnd)"
            let lower = cal.date(byAdding: .day, value: (c.weekStart - 1) * 7, to: first)!
            let upper = cal.date(byAdding: .day, value: c.weekEnd * 7 - 1, to: first)!
            func times(on date: Date) throws -> (Int, Int) {
                let month = cal.component(.month, from: date)
                let selected = seasonalTimeBlocks.map { (5...9).contains(month) ? $0.summer : $0.winter } ?? blocks
                guard let time = selected[key] else { throw invalid("请补全第 \(key) 节的时间。") }
                let start = try minute(time.start); let end = try minute(time.end)
                guard end > start else { throw invalid("第 \(key) 节结束时间必须晚于开始时间。") }
                return (start, end)
            }
            var rangeStart = lower
            var previous = try times(on: lower)
            var date = lower
            while date <= upper {
                let next = cal.date(byAdding: .day, value: 1, to: date)!
                let upcoming = try times(on: next)
                if next > upper || upcoming != previous {
                    result.courses.append(Course(title: c.title, weekday: c.weekday, start: previous.0, end: previous.1, location: c.location, semesterStart: rangeStart, semesterEnd: date))
                    rangeStart = next; previous = upcoming
                }
                date = next
            }
        }
        for t in todos {
            guard !t.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid("待办名称不能为空。") }
            var date: Date?
            if let value = t.due { date = ISO8601DateFormatter().date(from: value); guard date != nil else { throw invalid("待办截止时间必须是含时区的 ISO 8601 时间：\(value)") } }
            result.todos.append(Todo(title: t.title, course: t.course ?? "", due: date))
        }
        return result
    }
}
struct ImportTime: Codable { var start: String; var end: String }
struct ImportCourse: Codable {
    var title: String; var weekday: Int; var weekStart: Int; var weekEnd: Int
    var periodStart: Int; var periodEnd: Int; var location: String; var teachers: [String]
}
struct ImportTodo: Codable { var title: String; var course: String?; var due: String? }

// School timetable, not a change to the system time zone. May 1–Sep 30 = summer.
struct SeasonalTimes: Codable { var summer: [String: ImportTime]; var winter: [String: ImportTime] }
