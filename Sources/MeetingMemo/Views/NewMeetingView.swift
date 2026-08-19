import SwiftUI
import AppKit

// MARK: - New Meeting View

struct NewMeetingView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var meetingName: String = ""
    @State private var selectedTarget: CaptureTarget? = nil
    @State private var autoCaptureInterval: AutoCaptureInterval = .off
    @State private var isLoadingTargets: Bool = false
    @State private var captureTargets: [CaptureTarget] = []
    @State private var showPermissionAlert: Bool = false

    var onStart: ((String, CaptureTarget?, AutoCaptureInterval) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("新しい会議")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Meeting Name
                    FormField(label: "会議名") {
                        TextField("例）週次定例、プロジェクト打ち合わせ", text: $meetingName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Capture Target
                    FormField(label: "キャプチャ対象") {
                        if isLoadingTargets {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("ウィンドウを検索中...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if captureTargets.isEmpty {
                            Button("ウィンドウを取得") { loadTargets() }
                                .buttonStyle(.bordered)
                        } else {
                            Menu {
                                ForEach(groupedTargets, id: \.0) { group, targets in
                                    Section(group) {
                                        ForEach(targets) { target in
                                            Button(target.displayName) {
                                                selectedTarget = target
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    if let t = selectedTarget {
                                        VStack(alignment: .leading, spacing: 1) {
                                            if let app = t.applicationName {
                                                Text(app)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(t.displayName.count > 36 ? String(t.displayName.prefix(36)) + "…" : t.displayName)
                                                .font(.system(size: 13))
                                                .foregroundColor(.primary)
                                        }
                                    } else {
                                        Text("選択してください")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)   // ← 幅いっぱいに広げる
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                            }
                            .menuStyle(.automatic)
                        }
                    }

                    // Auto Screenshot
                    FormField(label: "自動スクリーンショット") {
                        HStack(spacing: 6) {
                            ForEach(AutoCaptureInterval.allCases, id: \.self) { interval in
                                Button(interval.rawValue) {
                                    autoCaptureInterval = interval
                                }
                                .buttonStyle(SegmentButtonStyle(isSelected: autoCaptureInterval == interval))
                            }
                        }
                    }

                    // Save path
                    FormField(label: "保存先") {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            Text(settings.savePath.abbreviatingWithTilde)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("変更...") { selectSavePath() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            Divider()

            // Start button
            HStack {
                if selectedTarget == nil && !captureTargets.isEmpty {
                    Text("キャプチャ対象を選択してください")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("会議を開始") {
                    startMeeting()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(captureTargets.isEmpty || selectedTarget == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 380, height: 400)
        .alert("画面収録の許可が必要です", isPresented: $showPermissionAlert) {
            Button("設定を開く") {
                CaptureManager.shared.requestPermission()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("キャプチャを使用するには、システム設定 > プライバシーとセキュリティ > 画面収録で「MacMeetingMemo」を許可してください。")
        }
        .onAppear {
            autoCaptureInterval = settings.autoCaptureInterval
            loadTargets()
        }
    }

    // MARK: - Grouped Targets

    private var groupedTargets: [(String, [CaptureTarget])] {
        var groups: [(String, [CaptureTarget])] = []
        let displays = captureTargets.filter { $0.type == .display }
        let windows = captureTargets.filter { $0.type == .window }

        if !displays.isEmpty {
            groups.append(("ディスプレイ", displays))
        }

        let appGroups = Dictionary(grouping: windows) { $0.applicationName ?? "その他" }
        for (app, targets) in appGroups.sorted(by: { $0.key < $1.key }) {
            groups.append((app, targets))
        }

        return groups
    }

    // MARK: - Actions

    private func loadTargets() {
        isLoadingTargets = true
        Task {
            let hasPermission = await CaptureManager.shared.checkPermission()
            if hasPermission {
                await CaptureManager.shared.loadAvailableTargets()
                await MainActor.run {
                    captureTargets = CaptureManager.shared.availableTargets
                    isLoadingTargets = false
                    // 既に選択済みの場合は変更しない（再読み込み時）
                    // 初回は自動選択しない → ユーザーが明示的に選ぶことを必須とする
                }
            } else {
                await MainActor.run {
                    isLoadingTargets = false
                    showPermissionAlert = true
                }
            }
        }
    }

    private func startMeeting() {
        onStart?(meetingName, selectedTarget, autoCaptureInterval)
        dismiss()
    }

    private func selectSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "保存先フォルダを選択してください"

        if panel.runModal() == .OK, let url = panel.url {
            settings.savePath = url
        }
    }
}

// MARK: - Form Field Helper

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            content
        }
    }
}

// MARK: - Segment Button Style

struct SegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - URL Extension

extension URL {
    var abbreviatingWithTilde: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
