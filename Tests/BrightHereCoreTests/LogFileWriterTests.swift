import Foundation
import Testing
@testable import BrightHereCore

@Suite("Log file writer")
struct LogFileWriterTests {
    @Test("appends log lines")
    func appendsLogLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("bright-here.log")
        let writer = LogFileWriter(fileURL: fileURL, maxBytes: 1024)

        writer.append("INFO first")
        writer.append("ERROR second")

        let text = writer.recentLogText(maxBytes: 1024)
        #expect(text.contains("INFO first"))
        #expect(text.contains("ERROR second"))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("rotates when log exceeds max size")
    func rotates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("bright-here.log")
        let previousURL = directory.appendingPathComponent("bright-here.previous.log")
        let writer = LogFileWriter(fileURL: fileURL, maxBytes: 20)

        writer.append(String(repeating: "x", count: 40))
        writer.append("after rotation")

        #expect(FileManager.default.fileExists(atPath: previousURL.path))
        #expect(writer.recentLogText(maxBytes: 1024).contains("after rotation"))
        try? FileManager.default.removeItem(at: directory)
    }
}
