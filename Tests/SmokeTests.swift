import Foundation
import AppKit
import PDFKit

@main struct SmokeTests {
    static func main() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))! }
        let course = Course(title: "高等数学", weekday: 4, start: 540, end: 630, location: "A101", semesterStart: date(1), semesterEnd: date(29))
        assert(course.occurs(on: date(29), calendar: cal))
        assert(!course.occurs(on: date(30), calendar: cal))
        assert(!course.occurs(on: date(8).addingTimeInterval(-86400 * 30), calendar: cal))
        let tasks = [Todo(title: "无日期", course: "", due: nil), Todo(title: "作业", course: "数学", due: date(29)), Todo(title: "完成", course: "", due: date(1), done: true)]
        let data = CampusData(courses: [course], todos: tasks)
        assert(data.pending.map(\.title) == ["作业", "无日期"])
        let decoded = try JSONDecoder().decode(CampusData.self, from: JSONEncoder().encode(data))
        assert(decoded == data)
        assert(clockText(545) == "09:05")
        do { _ = try JSONDecoder().decode(CampusData.self, from: Data("broken".utf8)); fatalError("Corrupt data accepted") } catch {}
        do { _ = try OCR.recognize(URL(fileURLWithPath: "/tmp/campus-no-such-image.png")); fatalError("Missing file accepted") } catch {}
        print("PASS: recurrence, semester boundaries, tasks, JSON round-trip, corrupt data, missing file")

        if CommandLine.arguments.contains("--models-only") { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CampusTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = NSImage(size: NSSize(width: 1200, height: 300))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 300).fill()
        ("Mathematics Homework Friday 09:00" as NSString).draw(at: NSPoint(x: 40, y: 130), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let png = directory.appendingPathComponent("fixture.png")
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: png)
        let recognized = try OCR.recognize(png)
        assert(recognized.lowercased().contains("mathematics"), recognized)
        print("PASS: image OCR → \(recognized)")
        let pdf = PDFDocument(); pdf.insert(PDFPage(image: image)!, at: 0)
        let pdfURL = directory.appendingPathComponent("scanned.pdf")
        assert(pdf.write(to: pdfURL))
        let pdfText = try OCR.recognize(pdfURL)
        assert(pdfText.lowercased().contains("mathematics"), pdfText)
        print("PASS: scanned PDF OCR")
    }
}
