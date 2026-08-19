import Foundation
import AppKit

// MARK: - File Output Manager

class FileOutputManager {
    static let shared = FileOutputManager()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Session Folder Creation

    func createSessionFolder(for session: Session, basePath: URL, appendName: Bool) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        var folderName = df.string(from: session.startedAt)
        if appendName && !session.name.isEmpty {
            let safe = session.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            folderName += "_\(safe)"
        }

        let sessionURL = basePath.appendingPathComponent(folderName)
        let capturesURL = sessionURL.appendingPathComponent("captures")

        try? FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)

        return sessionURL
    }

    // MARK: - Save Screenshot

    func saveScreenshot(image: NSImage, to sessionFolder: URL, format: CaptureFormat, at date: Date) -> String? {
        let df = DateFormatter()
        df.dateFormat = "HHmmssSSS"   // ミリ秒まで含めて同秒衝突を防ぐ
        let baseFilename = df.string(from: date)
        let capturesURL = sessionFolder.appendingPathComponent("captures")

        // 万一同ミリ秒でも衝突しないよう連番サフィックスを付ける
        var filename = "\(baseFilename).\(format.fileExtension)"
        var counter = 0
        while FileManager.default.fileExists(atPath: capturesURL.appendingPathComponent(filename).path) {
            counter += 1
            filename = "\(baseFilename)_\(counter).\(format.fileExtension)"
        }

        let fileURL = capturesURL.appendingPathComponent(filename)
        guard let data = imageData(from: image, format: format) else { return nil }
        do {
            try data.write(to: fileURL)
            return "captures/\(filename)"
        } catch {
            print("[FileOutputManager] Failed to save screenshot: \(error)")
            return nil
        }
    }

    private func imageData(from image: NSImage, format: CaptureFormat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        switch format {
        case .png:
            return bitmapRep.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
    }

    // MARK: - Save Memo Text

    func saveMemo(text: String, to sessionFolder: URL) {
        let fileURL = sessionFolder.appendingPathComponent("memo.txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Save session.md

    func saveSessionMarkdown(_ session: Session, to sessionFolder: URL) {
        var md = ""

        // Header
        let title = session.name.isEmpty ? "無題の会議" : session.name
        md += "# \(title)\n\n"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        md += "Started: \(df.string(from: session.startedAt))\n"
        if let ended = session.endedAt {
            md += "Ended: \(df.string(from: ended))\n"
        }
        md += "\n## Timeline\n\n"

        // Events timeline
        let timeDf = DateFormatter()
        timeDf.dateFormat = "HH:mm"

        for event in session.events {
            switch event.type {
            case .meetingStart:
                md += "\(timeDf.string(from: event.time))  \n会議開始\n\n"
            case .meetingEnd:
                md += "\(timeDf.string(from: event.time))  \n会議終了\n\n"
            case .memo:
                if let text = event.text, !text.isEmpty {
                    md += "\(timeDf.string(from: event.time))  \n\(text)\n\n"
                }
            case .screenshot, .autoScreenshot:
                if let file = event.file {
                    md += "![\(timeDf.string(from: event.time))](captures/\(URL(fileURLWithPath: file).lastPathComponent))\n\n"
                }
            case .ocrResult:
                if let text = event.text, !text.isEmpty {
                    // コードブロックで囲むことで # や * などMarkdown記号を無効化する
                    md += "🔍 OCR\n\n```\n\(text)\n```\n\n"
                }
            }
        }

        let fileURL = sessionFolder.appendingPathComponent("session.md")
        try? md.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Save session.json

    func saveSessionJSON(_ session: Session, to sessionFolder: URL) {
        struct SessionJSON: Encodable {
            let startedAt: String
            let endedAt: String?
            let meetingName: String
            let target: TargetJSON?
            let autoCaptureInterval: String
            let events: [EventJSON]

            struct TargetJSON: Encodable {
                let type: String
                let displayName: String
                let applicationName: String?
            }

            struct EventJSON: Encodable {
                let time: String
                let type: String
                let text: String?
                let file: String?
            }
        }

        let iso = ISO8601DateFormatter()

        let timeDf = DateFormatter()
        timeDf.dateFormat = "HH:mm:ss"

        let targetJSON: SessionJSON.TargetJSON? = session.captureTarget.map {
            SessionJSON.TargetJSON(
                type: $0.type.rawValue,
                displayName: $0.displayName,
                applicationName: $0.applicationName
            )
        }

        let eventsJSON = session.events.map { e in
            SessionJSON.EventJSON(
                time: timeDf.string(from: e.time),
                type: e.type.rawValue,
                text: e.text,
                file: e.file.map { URL(fileURLWithPath: $0).lastPathComponent }
            )
        }

        let obj = SessionJSON(
            startedAt: iso.string(from: session.startedAt),
            endedAt: session.endedAt.map { iso.string(from: $0) },
            meetingName: session.name,
            target: targetJSON,
            autoCaptureInterval: session.autoCaptureInterval.rawValue,
            events: eventsJSON
        )

        if let data = try? encoder.encode(obj) {
            let fileURL = sessionFolder.appendingPathComponent("session.json")
            try? data.write(to: fileURL)
        }
    }

    // MARK: - Load Recent Sessions

    func loadRecentSessions(from basePath: URL, limit: Int = 5) -> [Session] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: basePath, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ) else { return [] }

        let sessionFolders = contents
            .filter { $0.hasDirectoryPath }
            .compactMap { url -> (URL, Date)? in
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let date = attrs?[.creationDate] as? Date ?? Date.distantPast
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)

        return sessionFolders.compactMap { (url, _) in
            self.loadSession(from: url)
        }
    }

    // session.json から Session を完全復元する（captureTarget・events 含む）
    func loadSession(from url: URL) -> Session? {
        let jsonURL = url.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: jsonURL) else {
            return parseFolderNameSession(url: url)
        }

        // session.json の完全デコード用構造体
        struct FullSession: Decodable {
            let startedAt: String
            let endedAt: String?
            let meetingName: String
            let autoCaptureInterval: String?
            let target: TargetJSON?
            let events: [EventJSON]?

            struct TargetJSON: Decodable {
                let type: String
                let displayName: String
                let applicationName: String?
            }
            struct EventJSON: Decodable {
                let time: String        // "HH:mm:ss"
                let type: String
                let text: String?
                let file: String?
            }
        }

        let iso = ISO8601DateFormatter()
        guard let fs = try? JSONDecoder().decode(FullSession.self, from: data),
              let startDate = iso.date(from: fs.startedAt) else {
            return parseFolderNameSession(url: url)
        }

        // CaptureTarget 復元（windowID は保存していないので type/displayName/appName のみ）
        let captureTarget: CaptureTarget? = fs.target.map { t in
            CaptureTarget(
                type: CaptureTargetType(rawValue: t.type) ?? .display,
                displayName: t.displayName,
                applicationName: t.applicationName
            )
        }

        // AutoCaptureInterval 復元
        let interval = AutoCaptureInterval(rawValue: fs.autoCaptureInterval ?? "OFF") ?? .off

        var s = Session(
            name: fs.meetingName,
            startedAt: startDate,
            captureTarget: captureTarget,
            autoCaptureInterval: interval
        )
        s.folderPath = url
        if let endStr = fs.endedAt, let endDate = iso.date(from: endStr) {
            s.endedAt = endDate
        }

        // Events 復元（time は "HH:mm:ss" なので startedAt の日付部分と合成）
        let cal = Calendar.current
        let dateComponents = cal.dateComponents([.year, .month, .day], from: startDate)
        let timeDf = DateFormatter()
        timeDf.dateFormat = "HH:mm:ss"

        s.events = (fs.events ?? []).compactMap { e in
            guard let eventType = SessionEventType(rawValue: e.type) else { return nil }
            // 時刻を Date に変換（日付部分は startedAt と同じ）
            var eventDate = startDate
            if let parsedTime = timeDf.date(from: e.time) {
                var comps = cal.dateComponents([.hour, .minute, .second], from: parsedTime)
                comps.year  = dateComponents.year
                comps.month = dateComponents.month
                comps.day   = dateComponents.day
                eventDate = cal.date(from: comps) ?? startDate
            }
            let filePath = e.file.map { "captures/\($0)" }
            return SessionEvent(time: eventDate, type: eventType, text: e.text, file: filePath)
        }

        return s
    }

    private func parseFolderNameSession(url: URL) -> Session? {
        let name = url.lastPathComponent
        // Pattern: yyyy-MM-dd_HHmmss_meetingName
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        guard name.count >= 17 else { return nil }
        let dateStr = String(name.prefix(17))
        guard let date = df.date(from: dateStr) else { return nil }
        let meetingName = name.count > 18 ? String(name.dropFirst(18)) : ""
        var s = Session(name: meetingName, startedAt: date)
        s.folderPath = url
        return s
    }
}
