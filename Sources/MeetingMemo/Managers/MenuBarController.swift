import AppKit
import SwiftUI

// MARK: - Menu Bar Controller

@MainActor
class MenuBarController {
    private var statusItem: NSStatusItem?
    private var menuWindow: MenuBarWindow?
    private var controlBarWindowController: ControlBarWindowController?
    private var newMeetingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private let settings: AppSettings
    private let sessionManager: SessionManager

    init(settings: AppSettings) {
        self.settings = settings
        self.sessionManager = SessionManager.shared
    }

    // MARK: - Setup

    func setup() {
        setupStatusItem()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true
                button.image = img
            } else {
                // フォールバック: SF Symbols
                button.image = NSImage(systemSymbolName: "camera.and.pencil", accessibilityDescription: "MacMeetingMemo")
                button.image?.isTemplate = true
            }
            // 左クリック・右クリックどちらも同じアクション
            button.action = #selector(handleButtonClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    // MARK: - Toggle Menu Window

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        if let win = menuWindow, win.isVisible {
            win.orderOut(nil)
            menuWindow = nil
            return
        }
        showMenuWindow()
    }

    private func showMenuWindow() {
        guard let button = statusItem?.button,
              let screen = button.window?.screen ?? NSScreen.main else { return }

        sessionManager.loadRecentSessions()

        // コンテンツビューを作成
        let contentView = MenuBarPopoverView(
            onNewMeeting: { [weak self] in self?.showNewMeetingWindow() },
            onResumeSession: { [weak self] s in self?.resumeSession(s) },
            onOpenSettings: { [weak self] in self?.showSettingsWindow() }
        )
        .environmentObject(sessionManager)
        .environmentObject(settings)

        let win = MenuBarWindow()
        let hosting = NSHostingController(rootView: contentView)
        hosting.sizingOptions = .preferredContentSize
        win.contentViewController = hosting
        win.layoutIfNeeded()

        // ステータスバーボタンの画面座標を取得
        let btnFrame = button.convert(button.bounds, to: nil)
        guard let buttonScreenFrame = button.window?.convertToScreen(btnFrame) else { return }

        // ウィンドウサイズを決定
        let winSize = hosting.view.fittingSize
        let winWidth = max(winSize.width, 280)
        let winHeight = winSize.height

        // ウィンドウ左端をボタンの左端に合わせる（画面右端からはみ出す場合は右寄せ）
        var originX = buttonScreenFrame.minX
        if originX + winWidth > screen.visibleFrame.maxX {
            originX = screen.visibleFrame.maxX - winWidth
        }
        // ステータスバーの直下に配置
        let originY = buttonScreenFrame.minY - winHeight - 4

        win.setFrame(NSRect(x: originX, y: originY, width: winWidth, height: winHeight), display: false)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        menuWindow = win
    }

    // MARK: - New Meeting Window

    func showNewMeetingWindow() {
        menuWindow?.orderOut(nil)
        menuWindow = nil

        let contentView = NewMeetingView(
            onStart: { [weak self] name, target, interval in
                self?.startMeeting(name: name, target: target, interval: interval)
            }
        )
        .environmentObject(sessionManager)
        .environmentObject(settings)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "新しい会議"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        newMeetingWindow = window
    }

    // MARK: - Settings Window

    private func showSettingsWindow() {
        menuWindow?.orderOut(nil)
        menuWindow = nil

        let contentView = SettingsView()
            .environmentObject(settings)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "設定"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Start / Resume Meeting

    private func startMeeting(name: String, target: CaptureTarget?, interval: AutoCaptureInterval) {
        sessionManager.startSession(name: name, captureTarget: target, autoCaptureInterval: interval)
        showControlBar()
    }

    private func resumeSession(_ session: Session) {
        menuWindow?.orderOut(nil)
        menuWindow = nil
        sessionManager.resumeSession(session)
        showControlBar()
    }

    // MARK: - Control Bar

    private func showControlBar() {
        if controlBarWindowController == nil {
            controlBarWindowController = ControlBarWindowController.create(settings: settings)
        }
        controlBarWindowController?.updateAlwaysOnTop(settings.alwaysOnTop)
        controlBarWindowController?.show()
    }

    // MARK: - Update Status Icon When Recording

    func updateStatusIcon(isRecording: Bool) {
        if isRecording {
            // 録画中は赤丸 SF Symbol でステータスを示す
            statusItem?.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "MacMeetingMemo")
            statusItem?.button?.image?.isTemplate = false
        } else {
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true
                statusItem?.button?.image = img
            } else {
                statusItem?.button?.image = NSImage(systemSymbolName: "camera.and.pencil", accessibilityDescription: "MacMeetingMemo")
                statusItem?.button?.image?.isTemplate = true
            }
        }
    }
}

// MARK: - MenuBarWindow
// 吹き出しなし・角丸・transient（外クリックで閉じる）なカスタムウィンドウ

class MenuBarWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .transient]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    // フォーカスを失ったら自動的に閉じる
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
