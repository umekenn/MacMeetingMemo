import Foundation
import AppKit

// MARK: - App Settings

class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: Keys
    private enum Keys {
        static let savePath = "savePath"
        static let appendMeetingNameToFolder = "appendMeetingNameToFolder"
        static let autoCaptureInterval = "autoCaptureInterval"
        static let alwaysOnTop = "alwaysOnTop"
        static let menuBarResident = "menuBarResident"
        static let showDockIcon = "showDockIcon"
        static let captureFormat = "captureFormat"
        static let captureMode   = "captureMode"
    }

    @Published var savePath: URL {
        didSet { defaults.set(savePath.path, forKey: Keys.savePath) }
    }

    @Published var appendMeetingNameToFolder: Bool {
        didSet { defaults.set(appendMeetingNameToFolder, forKey: Keys.appendMeetingNameToFolder) }
    }

    @Published var autoCaptureInterval: AutoCaptureInterval {
        didSet { defaults.set(autoCaptureInterval.rawValue, forKey: Keys.autoCaptureInterval) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    @Published var menuBarResident: Bool {
        didSet { defaults.set(menuBarResident, forKey: Keys.menuBarResident) }
    }

    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: Keys.showDockIcon)
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(self.showDockIcon ? .regular : .accessory)
            }
        }
    }

    @Published var captureFormat: CaptureFormat {
        didSet { defaults.set(captureFormat.rawValue, forKey: Keys.captureFormat) }
    }

    @Published var captureMode: CaptureMode {
        didSet { defaults.set(captureMode.rawValue, forKey: Keys.captureMode) }
    }

    init() {
        // Default save path
        let defaultPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacMeetingMemo")
        let savedPath = defaults.string(forKey: Keys.savePath)
            .flatMap { URL(string: "file://\($0)") } ?? defaultPath
        self.savePath = savedPath

        self.appendMeetingNameToFolder = defaults.object(forKey: Keys.appendMeetingNameToFolder) as? Bool ?? true
        let intervalRaw = defaults.string(forKey: Keys.autoCaptureInterval) ?? AutoCaptureInterval.off.rawValue
        self.autoCaptureInterval = AutoCaptureInterval(rawValue: intervalRaw) ?? .off
        self.alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        self.menuBarResident = defaults.object(forKey: Keys.menuBarResident) as? Bool ?? true
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
        let formatRaw = defaults.string(forKey: Keys.captureFormat) ?? CaptureFormat.png.rawValue
        self.captureFormat = CaptureFormat(rawValue: formatRaw) ?? .png
        let modeRaw = defaults.string(forKey: Keys.captureMode) ?? CaptureMode.imageOnly.rawValue
        self.captureMode = CaptureMode(rawValue: modeRaw) ?? .imageOnly
    }
}

// MARK: - CaptureMode

enum CaptureMode: String, CaseIterable, Codable {
    /// 画像のみ保存。OCRは実行しない（既定）。
    case imageOnly = "imageOnly"
    /// 画像保存後、自動でOCRを実行してテキストを抽出する。
    case imageAndOCR = "imageAndOCR"

    var label: String {
        switch self {
        case .imageOnly:   return "画像のみ"
        case .imageAndOCR: return "画像＋文字抽出（OCR）"
        }
    }

    var description: String {
        switch self {
        case .imageOnly:   return "スクリーンショットを保存するだけ"
        case .imageAndOCR: return "キャプチャ後に自動でOCRを実行しテキストを抽出"
        }
    }
}

// MARK: - CaptureFormat

enum CaptureFormat: String, CaseIterable, Codable {
    case png = "PNG"
    case jpeg = "JPEG"

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}
