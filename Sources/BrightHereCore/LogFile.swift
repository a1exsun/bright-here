import Foundation

public protocol LogWriting {
    func append(_ message: String)
    func recentLogText(maxBytes: Int) -> String
}

public final class LogFileWriter: LogWriting {
    public let fileURL: URL
    private let maxBytes: UInt64
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let lock = NSLock()

    public init(
        fileURL: URL = LogFileWriter.defaultLogURL(),
        maxBytes: UInt64 = 512 * 1024,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public static func defaultLogURL() -> URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Bright Here", isDirectory: true)
        return logs.appendingPathComponent("bright-here.log")
    }

    public func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try rotateIfNeeded()
            let line = "\(Self.timestamp(dateProvider())) \(message)\n"
            let data = Data(line.utf8)
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL)
            }
        } catch {
            // Logging must never break brightness routing.
        }
    }

    public func recentLogText(maxBytes: Int = 64 * 1024) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: fileURL) else {
            return ""
        }
        let suffix = data.suffix(max(0, maxBytes))
        return String(decoding: suffix, as: UTF8.self)
    }

    private func rotateIfNeeded() throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? UInt64,
              size >= maxBytes
        else {
            return
        }

        let rotated = fileURL.deletingLastPathComponent().appendingPathComponent("bright-here.previous.log")
        if fileManager.fileExists(atPath: rotated.path) {
            try fileManager.removeItem(at: rotated)
        }
        try fileManager.moveItem(at: fileURL, to: rotated)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
