import AppKit
import PDFKit
import Vision

enum OCR {
    static func recognize(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else {
                throw failure("无法读取此 PDF。请确认文件未损坏或未加密。")
            }
            guard pdf.pageCount <= 40 else { throw failure("请将 PDF 拆分为每份不超过 40 页后导入。") }
            var pages: [String] = []
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { throw failure("无法读取第 \(i + 1) 页。") }
                let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if embedded.count >= 10 {
                    pages.append("—— 第 \(i + 1) 页 ——\n" + embedded)
                } else {
                    let bounds = page.bounds(for: .mediaBox)
                    let scale = min(3, 2600 / max(bounds.width, bounds.height))
                    let picture = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                    guard let cg = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw failure("第 \(i + 1) 页无法转换为图像。") }
                    pages.append("—— 第 \(i + 1) 页 ——\n" + (try text(cg)))
                }
            }
            return pages.joined(separator: "\n\n")
        }
        guard let picture = NSImage(contentsOf: url), let cg = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw failure("无法读取图片，请使用 PNG、JPEG 或 HEIC 文件。")
        }
        return try text(cg)
    }
    private static func text(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    private static func failure(_ text: String) -> Error {
        NSError(domain: "CampusDesk.OCR", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
