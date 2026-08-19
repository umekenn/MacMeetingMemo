import Foundation

// MARK: - Session Event Types

enum SessionEventType: String, Codable {
    case meetingStart = "meeting_start"
    case meetingEnd = "meeting_end"
    case memo = "memo"
    case screenshot = "screenshot"
    case autoScreenshot = "auto_screenshot"
    case ocrResult = "ocr_result"
}

// MARK: - Session Event

struct SessionEvent: Identifiable, Codable {
    let id: UUID
    let time: Date
    let type: SessionEventType
    var text: String?
    var file: String?

    init(id: UUID = UUID(), time: Date = Date(), type: SessionEventType, text: String? = nil, file: String? = nil) {
        self.id = id
        self.time = time
        self.type = type
        self.text = text
        self.file = file
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }

    var timeStringFull: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: time)
    }
}

// MARK: - Capture Target

enum CaptureTargetType: String, Codable {
    case window = "window"
    case application = "application"
    case display = "display"
}

struct CaptureTarget: Identifiable, Codable, Equatable {
    let id: UUID
    let type: CaptureTargetType
    let displayName: String
    let applicationName: String?
    let windowID: UInt32?
    let processID: Int32?

    init(id: UUID = UUID(), type: CaptureTargetType, displayName: String, applicationName: String? = nil, windowID: UInt32? = nil, processID: Int32? = nil) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.applicationName = applicationName
        self.windowID = windowID
        self.processID = processID
    }

    static func == (lhs: CaptureTarget, rhs: CaptureTarget) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Auto Capture Interval

enum AutoCaptureInterval: String, CaseIterable, Codable {
    case off = "OFF"
    case sec30 = "30秒"
    case min1 = "1分"
    case min5 = "5分"

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .sec30: return 30
        case .min1: return 60
        case .min5: return 300
        }
    }
}

// MARK: - Session

struct Session: Identifiable, Codable {
    let id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var folderPath: URL?
    var captureTarget: CaptureTarget?
    var autoCaptureInterval: AutoCaptureInterval
    var events: [SessionEvent]

    init(
        id: UUID = UUID(),
        name: String = "",
        startedAt: Date = Date(),
        captureTarget: CaptureTarget? = nil,
        autoCaptureInterval: AutoCaptureInterval = .off
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.captureTarget = captureTarget
        self.autoCaptureInterval = autoCaptureInterval
        self.events = []
    }

    var captureCount: Int {
        events.filter { $0.type == .screenshot || $0.type == .autoScreenshot }.count
    }

    var durationMinutes: Int {
        let end = endedAt ?? Date()
        return Int(end.timeIntervalSince(startedAt) / 60)
    }
}
