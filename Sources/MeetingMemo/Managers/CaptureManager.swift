import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

// MARK: - Capture Manager

@MainActor
class CaptureManager: ObservableObject {
    static let shared = CaptureManager()

    @Published var availableTargets: [CaptureTarget] = []
    @Published var hasPermission: Bool = false

    private init() {}

    // MARK: - Permission Check

    func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            hasPermission = true
            return true
        } catch {
            hasPermission = false
            return false
        }
    }

    func requestPermission() {
        // Open System Preferences for screen recording permission
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Load Available Targets

    func loadAvailableTargets() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            var targets: [CaptureTarget] = []

            // Add display targets — 実際の名前・解像度で識別できる表示にする
            let displays = content.displays.sorted { $0.displayID < $1.displayID }
            for display in displays {
                // NSScreen.localizedName で「内蔵Retinaディスプレイ」「LG Ultra HD」等の実名を取得
                let screenName: String = NSScreen.screens
                    .first(where: {
                        // NSScreen の displayID（CGDirectDisplayID）と SCDisplay.displayID を突き合わせ
                        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == display.displayID
                    })
                    .map { $0.localizedName }
                    ?? "ディスプレイ"
                // 解像度（ポイント数）を付加
                let label = "\(screenName) (\(display.width)×\(display.height))"
                let target = CaptureTarget(
                    type: .display,
                    displayName: label,
                    applicationName: nil,
                    windowID: display.displayID,   // displayID を windowID 欄に流用して識別
                    processID: nil
                )
                targets.append(target)
            }

            // 除外するシステムアプリのバンドルID
            let excludedBundleIDs: Set<String> = [
                "com.apple.controlcenter",
                "com.apple.notificationcenterui",
                "com.apple.WindowManager",
                "com.apple.dock",
                "com.apple.finder",
                "com.apple.systemuiserver",
                "com.apple.TextInputMenuAgent",
                "com.apple.Spotlight",
                // Dockの内部レンダリングに使われるXPCサービス群を除外
                "com.apple.dock.extra",
                "com.apple.dock.fullscreen",
            ]
            // 除外するウィンドウタイトル（部分一致）
            let excludedTitleKeywords: [String] = [
                "Offscreen Wallpaper Window",
                "Item-0",
                "Backstop",
                "Menubar",
                "StatusIndicator",
                "Notification Center",
            ]
            // 除外するウィンドウタイトル（完全一致）
            // "underbelly" は macOS のDock内部ウィンドウ名（SCKit が誤ってリストアップする）
            let excludedTitleExact: Set<String> = [
                "underbelly",
                "Dock",
            ]

            // Add window targets grouped by app
            let sortedApps = content.applications.sorted { $0.applicationName < $1.applicationName }
            for app in sortedApps {
                // バンドルIDで除外
                if excludedBundleIDs.contains(app.bundleIdentifier) { continue }

                let appWindows = content.windows.filter { $0.owningApplication?.processID == app.processID }
                for window in appWindows {
                    guard let title = window.title, !title.isEmpty else { continue }
                    // タイトルキーワードで除外（部分一致）
                    if excludedTitleKeywords.contains(where: { title.contains($0) }) { continue }
                    // タイトルで除外（完全一致）
                    if excludedTitleExact.contains(title) { continue }
                    // アプリ名で除外（underbelly のようにアプリ名とタイトルが一致するケース）
                    if excludedTitleExact.contains(app.applicationName) { continue }
                    // 数字のみ・"Item-" のようなシステム内部ウィンドウを除外
                    if title.allSatisfy({ $0.isNumber }) { continue }

                    let target = CaptureTarget(
                        type: .window,
                        displayName: title,
                        applicationName: app.applicationName,
                        windowID: window.windowID,
                        processID: Int32(app.processID)
                    )
                    targets.append(target)
                }
            }

            self.availableTargets = targets
            self.hasPermission = true
        } catch {
            print("[CaptureManager] Failed to load targets: \(error)")
            self.hasPermission = false
        }
    }

    // MARK: - Take Screenshot

    func takeScreenshot(target: CaptureTarget?) async -> NSImage? {
        if !hasPermission {
            _ = await checkPermission()
            if !hasPermission { return nil }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // キャプチャするウィンドウの実サイズ（points）を取得してピクセルサイズ計算に使う
            var captureRect: CGRect = .zero
            let filter: SCContentFilter

            if let target = target {
                switch target.type {
                case .window:
                    if let windowID = target.windowID,
                       let scWindow = content.windows.first(where: { $0.windowID == windowID }) {
                        filter = SCContentFilter(desktopIndependentWindow: scWindow)
                        captureRect = scWindow.frame
                    } else if let processID = target.processID,
                              let app = content.applications.first(where: { Int32($0.processID) == processID }) {
                        guard let display = content.displays.first else { return nil }
                        filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                        captureRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
                    } else {
                        guard let display = content.displays.first else { return nil }
                        filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                        captureRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
                    }
                case .application:
                    if let processID = target.processID,
                       let app = content.applications.first(where: { Int32($0.processID) == processID }),
                       let display = content.displays.first {
                        filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                        captureRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
                    } else {
                        guard let display = content.displays.first else { return nil }
                        filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                        captureRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
                    }
                case .display:
                    // windowID 欄に displayID を格納しているため、それで正しいディスプレイを特定
                    let display: SCDisplay
                    if let storedDisplayID = target.windowID,
                       let matched = content.displays.first(where: { $0.displayID == storedDisplayID }) {
                        display = matched
                    } else if let first = content.displays.first {
                        display = first
                    } else {
                        return nil
                    }
                    filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                    captureRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
                }
            } else {
                guard let display = content.displays.first else { return nil }
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                captureRect = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
            }

            if #available(macOS 14.0, *) {
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let config = SCStreamConfiguration()
                // ウィンドウの実サイズ × Retina スケールでピクセル数を設定する。
                // 固定値 2560×1440 を使うと全画面サイズで取得されて余白だらけになる。
                let pw = max(Int(captureRect.width  * scale), 1)
                let ph = max(Int(captureRect.height * scale), 1)
                config.width  = pw
                config.height = ph
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            } else {
                return captureWithCoreGraphics(target: target)
            }
        } catch {
            print("[CaptureManager] Screenshot failed: \(error)")
            // Fallback to CGWindowListCreateImage
            return captureWithCoreGraphics(target: target)
        }
    }

    // MARK: - CoreGraphics fallback

    private func captureWithCoreGraphics(target: CaptureTarget?) -> NSImage? {
        if let target = target, let windowID = target.windowID {
            // Capture specific window
            let cgWindowID = CGWindowID(windowID)
            if let image = CGWindowListCreateImage(
                CGRect.null,
                .optionIncludingWindow,
                cgWindowID,
                [.boundsIgnoreFraming]
            ) {
                return NSImage(cgImage: image, size: .zero)
            }
        }
        // Full screen fallback
        guard let screen = NSScreen.main else { return nil }
        let bounds = screen.frame
        if let image = CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) {
            return NSImage(cgImage: image, size: .zero)
        }
        return nil
    }
}
