import Foundation
@main struct ImportTests {
 static func main() throws {
  var doc = try JSONDecoder().decode(ScheduleImport.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
  let resolved = try doc.resolved(monday: doc.firstMonday!, blocks: [:])
  let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
  for (day, expected) in [("2026-09-28",870),("2026-10-05",840)] {
   let courses = resolved.courses.filter { $0.occurs(on: f.date(from: day)!) }
   assert(courses.count == 1 && courses[0].start == expected)
  }
  do { _ = try doc.resolved(monday: "2026-09-15", blocks: [:]); fatalError("Accepted non-Monday") } catch {}
  doc.seasonalTimeBlocks = nil
  do { _ = try doc.resolved(monday: doc.firstMonday!, blocks: [:]); fatalError("Accepted missing times") } catch {}
  let tasks = ScheduleImport(version: 1, term: "", campus: "", courses: [], todos: [ImportTodo(title: "示例待办", due: nil)])
  let data = try tasks.resolved(monday: "", blocks: [:]); assert(data.todos.count == 1)
  print("PASS: seasonal switch, no duplicate occurrence, date validation, standalone todos")
 }
}
