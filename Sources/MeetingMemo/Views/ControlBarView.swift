import SwiftUI
import AppKit

// MARK: - Floating Control Bar Window

class ControlBarWindowController: NSWindowController {
    private var settings: AppSettings?

    static func create(settings: AppSettings) -> ControlBarWindowController {
        let contentView = ControlBarView()
            .environmentObject(SessionManager.shared)
            .environmentObject(settings)

        let hostingView = SizingHostingView(rootView: contentView)
        hostingView.autoresizingMask = []

        let window = ControlBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.center()

        let controller = ControlBarWindowController(window: window)
        controller.settings = settings
        window.windowController = controller
        return controller
    }

    func updateAlwaysOnTop(_ alwaysOnTop: Bool) {
        window?.level = alwaysOnTop ? .floating : .normal
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Custom Panel (click-through background)

class ControlBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // sendEvent のオーバーライドは廃止。
    // IME（NSTextInputClient）はウィンドウがキーウィンドウである限り
    // NSTextView に自動的にルーティングされる。
    // 手動転送すると未確定文字（マークテキスト）が破壊されていた。

    /// nonactivatingPanel では SwiftUI の .contextMenu が発火しないため、
    /// rightMouseDown を直接ハンドルして NSMenu をポップアップする
    override func rightMouseDown(with event: NSEvent) {
        let menu = buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? self.contentView!)
    }

    private func buildContextMenu() -> NSMenu {
        let session = SessionManager.shared
        let menu = NSMenu()

        // スクリーンショット
        let captureItem = NSMenuItem(
            title: "スクリーンショットを撮影",
            action: #selector(ControlBarPanel.menuTakeScreenshot),
            keyEquivalent: ""
        )
        captureItem.target = self
        captureItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        menu.addItem(captureItem)

        // OCR
        let ocrItem = NSMenuItem(
            title: "直近キャプチャをOCR",
            action: #selector(ControlBarPanel.menuRunOCR),
            keyEquivalent: ""
        )
        ocrItem.target = self
        ocrItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
        let hasCapture = session.currentSession?.events.last(where: {
            $0.type == .screenshot || $0.type == .autoScreenshot
        }) != nil
        ocrItem.isEnabled = hasCapture
        menu.addItem(ocrItem)

        menu.addItem(.separator())

        // 自動キャプチャ間隔サブメニュー
        let intervalMenu = NSMenu()
        let current = session.currentSession?.autoCaptureInterval ?? .off
        for interval in AutoCaptureInterval.allCases {
            let item = NSMenuItem(
                title: interval.rawValue,
                action: #selector(ControlBarPanel.menuSetInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval
            if interval == current {
                item.state = .on
            }
            intervalMenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "自動キャプチャ間隔", action: nil, keyEquivalent: "")
        menu.addItem(intervalItem)
        menu.setSubmenu(intervalMenu, for: intervalItem)

        menu.addItem(.separator())

        // 会議終了
        let stopItem = NSMenuItem(
            title: "会議を終了",
            action: #selector(ControlBarPanel.menuStopMeeting),
            keyEquivalent: ""
        )
        stopItem.target = self
        stopItem.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
        menu.addItem(stopItem)

        return menu
    }

    @objc private func menuTakeScreenshot() {
        SessionManager.shared.takeManualScreenshot()
    }

    @objc private func menuRunOCR() {
        SessionManager.shared.runOCROnLatestCapture()
    }

    @objc private func menuSetInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? AutoCaptureInterval else { return }
        SessionManager.shared.changeAutoCaptureInterval(interval)
    }

    @objc private func menuStopMeeting() {
        SessionManager.shared.endSession()
        orderOut(nil)
    }
}

// MARK: - Hosting View that resizes its window to fit content

class SizingHostingView<Content: View>: NSHostingView<Content> {
    // layout() は1フレームに何度も呼ばれるため、実際にサイズが変わったときだけ
    // ウィンドウをリサイズする。頻繁なリサイズがヘッダーの「跳ね」を引き起こしていた。
    private var lastFittingSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard let window = window else { return }
        let size = fittingSize
        guard size.width > 10, size.height > 10 else { return }
        guard size != lastFittingSize else { return }   // 変化なければスキップ
        lastFittingSize = size

        let minWidth: CGFloat = 500
        let newWidth  = max(size.width, minWidth)
        let newHeight = size.height
        // ウィンドウ左上を固定してリサイズ（上端が動かないようにする）
        var frame = window.frame
        frame.origin.y = frame.maxY - newHeight   // 上端を保持
        frame.size = NSSize(width: newWidth, height: newHeight)
        window.setFrame(frame, display: true, animate: false)
    }
}

// MARK: - Control Bar View

struct ControlBarView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var settings: AppSettings
    @State private var isMemoExpanded: Bool = false
    @State private var showScreenshotFlash: Bool = false
    @State private var showIntervalMenu: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Main Bar
            mainBarRow

            // Memo Expanded Area
            if isMemoExpanded {
                Divider()
                    .background(Color(NSColor.separatorColor))
                memoArea
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(minWidth: 480)
        .overlay(
            // Screenshot flash feedback
            Group {
                if showScreenshotFlash {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                        .transition(.opacity)
                }
            }
        )
        // 右クリックでもコントロールバーのコンテキストメニューを表示
        .contextMenu {
            controlBarContextMenuItems
        }
    }

    // MARK: - Context Menu Items（左右クリック共通）

    @ViewBuilder
    private var controlBarContextMenuItems: some View {
        Button {
            takeScreenshot()
        } label: {
            Label("スクリーンショットを撮影", systemImage: "camera")
        }
        Button {
            session.runOCROnLatestCapture()
        } label: {
            Label("直近キャプチャをOCR", systemImage: "text.viewfinder")
        }
        .disabled(session.currentSession?.events.last(where: {
            $0.type == .screenshot || $0.type == .autoScreenshot
        }) == nil)
        Divider()
        Menu("自動キャプチャ間隔") {
            let current = session.currentSession?.autoCaptureInterval ?? .off
            ForEach(AutoCaptureInterval.allCases, id: \.self) { interval in
                Button {
                    session.changeAutoCaptureInterval(interval)
                } label: {
                    if interval == current {
                        Label(interval.rawValue, systemImage: "checkmark")
                    } else {
                        Text(interval.rawValue)
                    }
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            stopMeeting()
        } label: {
            Label("会議を終了", systemImage: "stop.circle")
        }
    }

    // MARK: - Main Bar Row

    private var mainBarRow: some View {
        HStack(spacing: 0) {
            // Recording indicator + elapsed time
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(session.isRecording ? 1.0 : 0.3)
                    .modifier(BlinkingModifier(isBlinking: session.isRecording))

                Text(session.elapsedTimeFormatted)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 80)

            Divider()
                .frame(height: 20)
                .background(Color(NSColor.separatorColor))

            // Capture target
            HStack(spacing: 4) {
                if let target = session.currentSession?.captureTarget {
                    if let appName = target.applicationName {
                        Text(appName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Text(target.displayName.count > 20 ? String(target.displayName.prefix(20)) + "…" : target.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    Text("未設定")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 200, alignment: .leading)

            Divider()
                .frame(height: 20)
                .background(Color(NSColor.separatorColor))

            // キャプチャ枚数バッジ
            HStack(spacing: 3) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("\(session._captureCount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 42)

            Spacer()

            // 自動キャプチャ間隔インジケーター（タップで変更メニュー）
            autoCaptureIntervalButton

            // Screenshot button
            cameraButton

            // Memo button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMemoExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 14, weight: .medium))
                    Text("Memo")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(isMemoExpanded ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isMemoExpanded ? Color.blue : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isMemoExpanded ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("メモを展開")

            // Stop button
            Button {
                stopMeeting()
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                    )
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("会議を終了")
        }
        .frame(height: 48)
    }

    // MARK: - Memo Area

    private var memoArea: some View {
        VStack(spacing: 0) {
            MemoTextView(
                text: $session.memoText,
                scrollToEndTrigger: session.scrollToEndTrigger,
                onSave: { session.saveMemoText() }
            )
            .frame(minHeight: 120, maxHeight: 200)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Status bar
            HStack {
                Text("保存済み ✓")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(Date(), style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isMemoExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Auto Capture Interval Button

    /// 現在の自動キャプチャ設定を表示。クリックで間隔変更メニューを表示。
    private var autoCaptureIntervalButton: some View {
        let current = session.currentSession?.autoCaptureInterval ?? .off
        return Menu {
            ForEach(AutoCaptureInterval.allCases, id: \.self) { interval in
                Button {
                    session.changeAutoCaptureInterval(interval)
                } label: {
                    if interval == current {
                        Label(interval.rawValue, systemImage: "checkmark")
                    } else {
                        Text(interval.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                Text(current == .off ? "手動" : current.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(current == .off ? .secondary : .blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(current == .off
                          ? Color(NSColor.controlBackgroundColor)
                          : Color.blue.opacity(0.12))
            )
        }
        .menuStyle(.automatic)
        .help("自動キャプチャ間隔を変更")
    }

    // MARK: - Camera Button（タップ: キャプチャ / 長押し: OCR）

    private var cameraButton: some View {
        Button {
            takeScreenshot()
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("スクリーンショット（長押しで直近キャプチャをOCR）")
        .contextMenu {
            Button {
                takeScreenshot()
            } label: {
                Label("スクリーンショットを撮影", systemImage: "camera")
            }
            Divider()
            Button {
                session.runOCROnLatestCapture()
            } label: {
                Label("直近キャプチャをOCR（文字起こし）", systemImage: "text.viewfinder")
            }
            .disabled(session.currentSession?.events.last(where: {
                $0.type == .screenshot || $0.type == .autoScreenshot
            }) == nil)
        }
    }

    // MARK: - Actions

    private func takeScreenshot() {
        session.takeManualScreenshot()
        withAnimation {
            showScreenshotFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showScreenshotFlash = false
            }
        }
    }

    private func stopMeeting() {
        session.endSession()
        NSApp.windows.first(where: { $0 is ControlBarPanel })?.orderOut(nil)
    }
}

// MARK: - MemoScrollView
// mouseDown でキーウィンドウ昇格 + firstResponder 設定を確実に行う NSScrollView サブクラス

class MemoScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        // nonactivatingPanel でもクリック時にキーウィンドウにする。
        // すでにキーウィンドウの場合は makeKey() を呼ばない。
        // （呼ぶたびに IMK Mach ポート通知が走り、初回接続前は stderr にログが出るため）
        let win = window
        if win?.isKeyWindow == false {
            win?.makeKey()
        }
        if let tv = documentView as? NSTextView, win?.firstResponder !== tv {
            win?.makeFirstResponder(tv)
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Memo Text View (NSTextView wrapper)

struct MemoTextView: NSViewRepresentable {
    @Binding var text: String
    var scrollToEndTrigger: Int = 0
    var onSave: () -> Void

    func makeNSView(context: Context) -> MemoScrollView {
        let scrollView = MemoScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // 初期テキストをセット
        textView.string = text

        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: MemoScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // IME未確定文字（マークテキスト）が存在する間は一切更新しない
        if textView.hasMarkedText() { return }

        let triggerChanged = scrollToEndTrigger != context.coordinator.lastScrollToEndTrigger

        if triggerChanged {
            // キャプチャ/OCR 完了トリガー: テキストを反映してカーソルを末尾へ
            context.coordinator.lastScrollToEndTrigger = scrollToEndTrigger
            if textView.string != text {
                applyDiff(to: textView, newText: text)
            }
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            // フォーカスを textView に移して即入力できる状態にする
            if let win = textView.window {
                if !win.isKeyWindow { win.makeKey() }
                win.makeFirstResponder(textView)
            }
            return
        }

        // 通常の外部テキスト更新
        guard textView.string != text else { return }

        let isFocused = textView.window?.firstResponder === textView
        let savedSelection = textView.selectedRange()

        if isFocused {
            applyDiff(to: textView, newText: text)
            let count = (textView.string as NSString).length
            let loc = min(savedSelection.location, count)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
        } else {
            textView.string = text
            let end = (textView.string as NSString).length
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - 差分適用ヘルパー

    /// 既存テキストと newText を比較し、末尾追記 / 部分置換を textStorage で行う。
    /// textView.string への直接代入を避けることで firstResponder とIMEを保護する。
    private func applyDiff(to textView: NSTextView, newText: String) {
        guard let storage = textView.textStorage else { return }

        // NSString（UTF16）ベースで共通プレフィックス長を求める
        let oldNS = textView.string as NSString
        let newNS = newText as NSString
        let oldLen = oldNS.length
        let newLen = newNS.length
        var commonLen = 0
        let minLen = min(oldLen, newLen)
        while commonLen < minLen && oldNS.character(at: commonLen) == newNS.character(at: commonLen) {
            commonLen += 1
        }

        // 削除範囲と挿入文字列
        let deleteRange = NSRange(location: commonLen, length: oldLen - commonLen)
        let insertText = newNS.substring(from: commonLen)

        storage.beginEditing()
        storage.replaceCharacters(
            in: deleteRange,
            with: NSAttributedString(
                string: insertText,
                attributes: [.font: NSFont.systemFont(ofSize: 13)]
            )
        )
        storage.endEditing()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MemoTextView
        var lastScrollToEndTrigger: Int = 0

        init(_ parent: MemoTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // IME確定中（マークテキストあり）は binding に反映しない
            if tv.hasMarkedText() { return }
            parent.text = tv.string
            parent.onSave()
        }

        // MARK: - マーカー行の編集保護
        // 📷・🔍 で始まる行への変更操作をブロックする

        func textView(_ textView: NSTextView,
                      shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let storage = textView.textStorage else { return true }
            let fullText = storage.string as NSString

            // nil replacementString = IMEの確定操作など → 常に許可
            guard let replacement = replacementString else { return true }

            // 変更範囲が空かつ挿入なしはカーソル移動のみ → 許可
            if affectedCharRange.length == 0 && replacement.isEmpty { return true }

            // 変更が影響する行を調べる
            let checkStart = max(0, affectedCharRange.location)
            let checkRange = NSRange(location: checkStart, length: max(1, affectedCharRange.length))
            let safeRange = NSRange(
                location: checkRange.location,
                length: min(checkRange.length, fullText.length - checkRange.location)
            )
            guard safeRange.location >= 0, safeRange.length >= 0,
                  safeRange.location + safeRange.length <= fullText.length else { return true }

            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            fullText.getLineStart(&lineStart, end: &lineEnd,
                                  contentsEnd: &contentsEnd,
                                  for: safeRange)
            let linesText = fullText.substring(
                with: NSRange(location: lineStart, length: lineEnd - lineStart)
            )

            for line in linesText.components(separatedBy: "\n") {
                if line.hasPrefix("📷 ") || line.hasPrefix("🔍 ") {
                    NSSound.beep()
                    return false
                }
            }
            return true
        }
    }
}

// MARK: - Blinking Modifier

struct BlinkingModifier: ViewModifier {
    let isBlinking: Bool
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                guard isBlinking else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    opacity = 0.2
                }
            }
            .onChange(of: isBlinking) { newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        opacity = 0.2
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        opacity = 1.0
                    }
                }
            }
    }
}
