import AppKit
import SwiftUI
import Combine

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let settings = AppSettings()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure activation policy (no Dock icon by default)
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)

        // Configure session manager
        Task { @MainActor in
            SessionManager.shared.configure(settings: settings)
        }

        // Setup menu bar
        let controller = MenuBarController(settings: settings)
        self.menuBarController = controller
        controller.setup()

        // Observe recording state for icon update
        Task { @MainActor in
            SessionManager.shared.$isRecording
                .sink { [weak controller] isRecording in
                    controller?.updateStatusIcon(isRecording: isRecording)
                }
                .store(in: &cancellables)
        }

        // Create save directory if needed
        try? FileManager.default.createDirectory(at: settings.savePath, withIntermediateDirectories: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save session if recording on quit
        Task { @MainActor in
            if SessionManager.shared.isRecording {
                SessionManager.shared.endSession()
            }
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }
}

// MARK: - App Entry Point

// AppDelegate をグローバルで保持 (NSApp.delegate は weak なので必須)
private let _appDelegate = AppDelegate()

@main
struct MeetingMemoApp {
    static func main() {
        let app = NSApplication.shared
        app.delegate = _appDelegate
        app.run()
    }
}
