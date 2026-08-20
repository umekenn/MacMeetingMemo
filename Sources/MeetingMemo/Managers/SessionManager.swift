import Foundation
import Combine
import AppKit
import ScreenCaptureKit

// MARK: - Session Manager

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var currentSession: Session? {
        didSet {
            // captureCount を currentSession 変化時に同期更新する
            // SwiftUI が currentSession 全体を再評価するより先に独立プロパティを確定させることで
            // コントロールバーの枚数表示が一瞬リセットして見える現象を防ぐ
            _captureCount = currentSession?.captureCount ?? 0
        }
    }
    @Published var isRecording: Bool = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var memoText: String = ""
    @Published var recentSessions: [Session] = []
    /// コントロールバーに直接バインドするキャプチャ枚数（currentSession.captureCount の安定コピー）
    @Published private(set) var _captureCount: Int = 0
    /// メモ欄のカーソルを末尾に移動させたいタイミングで増加させる
    @Published var scrollToEndTrigger: Int = 0

    private var timer: Timer?
    private var autoCaptureTimer: Timer?
    private var windowWatcherTimer: Timer?
    private var settings: AppSettings?

    private init() {}

    func configure(settings: AppSettings) {
        self.settings = settings
        loadRecentSessions()
    }

    // MARK: - Start Session

    func startSession(name: String, captureTarget: CaptureTarget?, autoCaptureInterval: AutoCaptureInterval) {
        let session = Session(
            name: name,
            startedAt: Date(),
            captureTarget: captureTarget,
            autoCaptureInterval: autoCaptureInterval
        )
        currentSession = session
        memoText = ""

        // Create folder
        guard let settings = settings else { return }
        let folder = FileOutputManager.shared.createSessionFolder(
            for: session,
            basePath: settings.savePath,
            appendName: settings.appendMeetingNameToFolder
        )
        currentSession?.folderPath = folder

        // Add start event
        appendEvent(SessionEvent(type: .meetingStart))

        // Start timers
        isRecording = true
        elapsedTime = 0
        startTimers(autoCaptureInterval: autoCaptureInterval)

        // Save initial
        saveSession()
    }

    // MARK: - Resume Session

    func resumeSession(_ session: Session) {
        var s = session
        s.endedAt = nil
        currentSession = s
        // memo.txt の内容をテキストエリアに復元
        memoText = loadMemoText(from: s)

        isRecording = true
        elapsedTime = Date().timeIntervalSince(s.startedAt)

        let interval = s.autoCaptureInterval
        startTimers(autoCaptureInterval: interval)

        // 再開マーカーを events に追加（既存 events は保持）
        appendEvent(SessionEvent(type: .memo, text: "--- 再開 \(Date().formatted(date: .omitted, time: .shortened)) ---"))

        // captureTarget の windowID が失われているため、現在開いているウィンドウで再マッチング
        if let saved = s.captureTarget, saved.windowID == nil {
            Task {
                await CaptureManager.shared.loadAvailableTargets()
                let refreshed = await MainActor.run {
                    // アプリ名とウィンドウタイトルが一致するものを探す
                    CaptureManager.shared.availableTargets.first { t in
                        t.applicationName == saved.applicationName && t.displayName == saved.displayName
                    } ?? CaptureManager.shared.availableTargets.first { t in
                        // タイトルが変わっていてもアプリが同じならそちらを使う
                        t.applicationName == saved.applicationName && t.type == .window
                    }
                }
                await MainActor.run {
                    if let found = refreshed {
                        self.currentSession?.captureTarget = found
                    }
                    self.saveSession()
                }
            }
        } else {
            saveSession()
        }
    }

    // MARK: - End Session

    func endSession() {
        guard var session = currentSession else { return }
        session.endedAt = Date()
        currentSession = session
        appendEvent(SessionEvent(type: .meetingEnd))

        stopTimers()
        isRecording = false

        saveSession()
        loadRecentSessions()
    }

    // MARK: - Manual Screenshot

    func takeManualScreenshot() {
        guard let session = currentSession, let folder = session.folderPath else { return }
        Task {
            if let image = await CaptureManager.shared.takeScreenshot(target: session.captureTarget) {
                let capturedAt = Date()
                let settings = await MainActor.run { self.settings }
                let format = settings?.captureFormat ?? .png
                let mode   = settings?.captureMode   ?? .imageOnly
                if let relativePath = FileOutputManager.shared.saveScreenshot(image: image, to: folder, format: format, at: capturedAt) {
                    await MainActor.run {
                        let event = SessionEvent(time: capturedAt, type: .screenshot, file: relativePath)
                        self.currentSession?.events.append(event)
                        // マーカーは常に挿入（どちらのモードでも📷タイムスタンプは記録）
                        self.insertCaptureMarker(relativePath: relativePath, at: capturedAt)
                        self.saveSession()
                        // imageAndOCR モードなら自動でOCRも実行
                        if mode == .imageAndOCR {
                            self.runOCROnLatestCapture()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Auto Screenshot

    private func takeAutoScreenshot() {
        guard let session = currentSession, let folder = session.folderPath else { return }
        Task {
            if let image = await CaptureManager.shared.takeScreenshot(target: session.captureTarget) {
                let capturedAt = Date()
                let settings = await MainActor.run { self.settings }
                let format = settings?.captureFormat ?? .png
                let mode   = settings?.captureMode   ?? .imageOnly
                if let relativePath = FileOutputManager.shared.saveScreenshot(image: image, to: folder, format: format, at: capturedAt) {
                    await MainActor.run {
                        let event = SessionEvent(time: capturedAt, type: .autoScreenshot, file: relativePath)
                        self.currentSession?.events.append(event)
                        self.insertCaptureMarker(relativePath: relativePath, at: capturedAt)
                        self.saveSession()
                        if mode == .imageAndOCR {
                            self.runOCROnLatestCapture()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Insert Capture Marker into Memo Text

    /// キャプチャが撮れたらメモテキストの末尾にマーカー行を挿入する。
    private func insertCaptureMarker(relativePath: String, at date: Date) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let filename = URL(fileURLWithPath: relativePath).lastPathComponent
        let prefix = memoText.isEmpty ? "" : "\n"
        memoText += "\(prefix)📷 \(df.string(from: date))  [\(filename)]\n"
        // メモ欄のカーソルをマーカー直後（末尾）に移動
        scrollToEndTrigger += 1
    }

    // MARK: - Save Memo

    func saveMemoText() {
        guard let folder = currentSession?.folderPath else { return }
        FileOutputManager.shared.saveMemo(text: memoText, to: folder)
        // memoText をパースして events の memo/ocr_result を更新
        syncEventsFromMemoText()
        saveSession()
    }

    // MARK: - Sync events from memoText

    /// memoText（UI バッファ）を 📷 マーカーで区切りパースし、
    /// 各キャプチャ間のテキストを対応する memo/ocr_result イベントに反映する。
    /// これにより session.json の events が正しい粒度で記録される。
    private func syncEventsFromMemoText() {
        guard var session = currentSession else { return }

        // memo イベントのみ除去して再構築する。
        // ocrResult は runOCROnLatestCapture() が直接 append しており、
        // ここで削除すると OCR 完了直後に saveSession() が呼ばれたとき
        // 結果が消えてしまうバグの原因になるため除去しない。
        session.events.removeAll { e in
            e.type == .memo
        }

        // memoText を行単位で処理し、📷 マーカーで区切る
        // 各セクション: (キャプチャファイル名 or nil, そのあとのテキスト行配列)
        struct Section {
            var filename: String?   // nil = 最初のキャプチャ前
            var captureTime: Date?
            var lines: [String]
        }

        var sections: [Section] = [Section(filename: nil, captureTime: nil, lines: [])]
        let allLines = memoText.components(separatedBy: "\n")

        for line in allLines {
            // 📷 マーカー行を検出: "📷 HH:mm  [filename.png]"
            if line.hasPrefix("📷 "), let filename = extractFilename(from: line) {
                // 新セクションを開始
                let captureDate = extractTime(from: line)
                sections.append(Section(filename: filename, captureTime: captureDate, lines: []))
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }

        let df = DateFormatter()
        df.dateFormat = "HH:mm"

        for section in sections {
            var memoLines: [String] = []
            for line in section.lines {
                // 🔍 行はメモから除外（OCR はすでに events に直接記録される）
                if line.hasPrefix("🔍 ") { continue }
                memoLines.append(line)
            }

            let memoTrimmed = memoLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // キャプチャイベントの時刻を基準時刻として使う
            let baseTime: Date = {
                if let fn = section.filename,
                   let capEvent = currentSession?.events.first(where: {
                       ($0.type == .screenshot || $0.type == .autoScreenshot)
                       && $0.file.map { URL(fileURLWithPath: $0).lastPathComponent } == fn
                   }) {
                    return capEvent.time.addingTimeInterval(0.5)  // キャプチャ直後
                }
                return section.captureTime ?? Date()
            }()

            if !memoTrimmed.isEmpty && !memoTrimmed.starts(with: "---") {
                session.events.append(SessionEvent(
                    time: baseTime,
                    type: .memo,
                    text: memoTrimmed
                ))
            }
        }

        // 再度時系列ソート
        session.events.sort { $0.time < $1.time }
        currentSession = session
    }

    /// "📷 23:13  [231301662.png]" からファイル名を抽出
    private func extractFilename(from markerLine: String) -> String? {
        guard let lb = markerLine.firstIndex(of: "["),
              let rb = markerLine.firstIndex(of: "]"),
              lb < rb else { return nil }
        let name = String(markerLine[markerLine.index(after: lb)..<rb])
        return name.isEmpty ? nil : name
    }

    /// "📷 23:13  [...]" から時刻 Date を抽出（日付は today）
    private func extractTime(from markerLine: String) -> Date? {
        // "📷 " の後の5文字が "HH:mm"
        let stripped = markerLine.dropFirst(3)  // "📷 " = emoji(2) + space(1) = UTF-8 で3文字扱い
        guard stripped.count >= 5 else { return nil }
        let timeStr = String(stripped.prefix(5))
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.date(from: timeStr)
    }

    // MARK: - OCR on latest screenshot

    func runOCROnLatestCapture() {
        guard let folder = currentSession?.folderPath else { return }
        guard let lastCapEvent = currentSession?.events.last(where: {
            $0.type == .screenshot || $0.type == .autoScreenshot
        }), let relPath = lastCapEvent.file else { return }

        let filename = URL(fileURLWithPath: relPath).lastPathComponent
        let imageURL = folder.appendingPathComponent(relPath)

        // OCR 中マーカーを挿入（処理中であることを示す）
        let pendingMarker = "🔍 OCR認識中... [\(filename)]\n"
        // 完了後は改行を付けてカーソルが次行に移動できるようにする
        let doneMarker    = "🔍 OCR認識完了 [\(filename)]\n\n"

        let prefix = memoText.hasSuffix("\n") ? "" : "\n"
        memoText += "\(prefix)\(pendingMarker)"

        Task {
            let ocrText = await OCRManager.recognizeText(from: imageURL)
            await MainActor.run {
                // 「認識中」→「認識完了\n\n」に表示を差し替え（メモ欄はこれだけ）
                self.memoText = self.memoText.replacingOccurrences(
                    of: pendingMarker,
                    with: doneMarker
                )
                // OCR 本文は events にのみ記録する（メモ欄に全文は出さない）
                if let text = ocrText, !text.isEmpty {
                    let captureTime = lastCapEvent.time
                    let ocrEvent = SessionEvent(
                        time: captureTime.addingTimeInterval(1),
                        type: .ocrResult,
                        text: text,
                        file: relPath
                    )
                    self.currentSession?.events.append(ocrEvent)
                }
                self.saveSession()
                // カーソルを末尾（空行）へ移動してすぐ入力できる状態にする
                self.scrollToEndTrigger += 1
            }
        }
    }

    // MARK: - Append Event

    private func appendEvent(_ event: SessionEvent) {
        currentSession?.events.append(event)
    }

    // MARK: - Change Auto Capture Interval (mid-session)

    func changeAutoCaptureInterval(_ newInterval: AutoCaptureInterval) {
        guard isRecording else { return }
        currentSession?.autoCaptureInterval = newInterval
        // 既存の自動キャプチャタイマーだけ張り直す
        autoCaptureTimer?.invalidate()
        autoCaptureTimer = nil
        if let seconds = newInterval.seconds {
            autoCaptureTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.takeAutoScreenshot()
                }
            }
        }
        saveSession()
    }

    // MARK: - Timers

    private func startTimers(autoCaptureInterval: AutoCaptureInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedTime += 1
            }
        }

        autoCaptureTimer?.invalidate()
        if let seconds = autoCaptureInterval.seconds {
            autoCaptureTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.takeAutoScreenshot()
                }
            }
        }

        startWindowWatcher()
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        autoCaptureTimer?.invalidate()
        autoCaptureTimer = nil
        windowWatcherTimer?.invalidate()
        windowWatcherTimer = nil
    }

    // MARK: - Window Watcher

    /// キャプチャ対象ウィンドウが閉じられたことを検知して自動で会議を終了する。
    /// ディスプレイキャプチャの場合は監視しない。
    private func startWindowWatcher() {
        windowWatcherTimer?.invalidate()
        windowWatcherTimer = nil

        // ウィンドウ選択時のみ監視する
        guard let target = currentSession?.captureTarget,
              target.type == .window,
              let watchedWindowID = target.windowID else { return }

        windowWatcherTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    let stillExists = content.windows.contains { $0.windowID == watchedWindowID }
                    if !stillExists {
                        // ウィンドウが消えた → 自動終了
                        self.endSession()
                    }
                } catch {
                    // SCShareableContent の取得失敗は無視（一時的なエラーの可能性）
                }
            }
        }
    }

    // MARK: - Persistence Helpers

    private func saveSession() {
        guard let session = currentSession, let folder = session.folderPath else { return }
        FileOutputManager.shared.saveSessionMarkdown(session, to: folder)
        FileOutputManager.shared.saveSessionJSON(session, to: folder)
        FileOutputManager.shared.saveMemo(text: memoText, to: folder)
    }

    private func loadMemoText(from session: Session) -> String {
        guard let folder = session.folderPath else { return "" }
        let fileURL = folder.appendingPathComponent("memo.txt")
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func loadRecentSessions() {
        guard let settings = settings else { return }
        recentSessions = FileOutputManager.shared.loadRecentSessions(from: settings.savePath)
    }

    // MARK: - Elapsed Time Formatted

    var elapsedTimeFormatted: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

}
