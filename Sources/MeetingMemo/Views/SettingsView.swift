import SwiftUI
import AppKit

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ─── 保存 ────────────────────────────────────────
            SettingsSectionHeader("保存")

            SettingsRow {
                Image(systemName: "folder")
                    .settingsIcon()
                Text("保存先")
                    .settingsLabel()
                Spacer()
                Text(settings.savePath.abbreviatingWithTilde)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
                Button("変更...") { selectSavePath() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            SettingsDivider()

            SettingsRow {
                Image(systemName: "textformat")
                    .settingsIcon()
                Text("会議名をフォルダ名へ追加")
                    .settingsLabel()
                Spacer()
                Toggle("", isOn: $settings.appendMeetingNameToFolder)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            // ─── キャプチャ ──────────────────────────────────
            SettingsSectionHeader("キャプチャ")

            SettingsRow {
                Image(systemName: "camera.on.rectangle")
                    .settingsIcon()
                Text("自動キャプチャ")
                    .settingsLabel()
                Spacer()
                Picker("", selection: $settings.autoCaptureInterval) {
                    ForEach(AutoCaptureInterval.allCases, id: \.self) { i in
                        Text(i.rawValue).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .labelsHidden()
            }

            SettingsDivider()

            SettingsRow {
                Image(systemName: "photo")
                    .settingsIcon()
                Text("キャプチャ形式")
                    .settingsLabel()
                Spacer()
                Picker("", selection: $settings.captureFormat) {
                    ForEach(CaptureFormat.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .labelsHidden()
            }

            SettingsDivider()

            VStack(alignment: .leading, spacing: 6) {
                SettingsRow {
                    Image(systemName: "doc.text.image")
                        .settingsIcon()
                    Text("キャプチャ動作")
                        .settingsLabel()
                    Spacer()
                }
                // セグメントの代わりにラジオボタン風の選択肢（説明付き）
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Button {
                        settings.captureMode = mode
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: settings.captureMode == mode
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(settings.captureMode == mode ? .blue : .secondary)
                                .frame(width: 18, alignment: .center)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.label)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)

            // ─── 表示 ────────────────────────────────────────
            SettingsSectionHeader("表示")

            SettingsRow {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .settingsIcon()
                Text("常に最前面")
                    .settingsLabel()
                Spacer()
                Toggle("", isOn: $settings.alwaysOnTop)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            SettingsDivider()

            SettingsRow {
                Image(systemName: "menubar.rectangle")
                    .settingsIcon()
                Text("メニューバー常駐")
                    .settingsLabel()
                Spacer()
                Toggle("", isOn: $settings.menuBarResident)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            SettingsDivider()

            SettingsRow {
                Image(systemName: "dock.rectangle")
                    .settingsIcon()
                Text("Dockアイコン表示")
                    .settingsLabel()
                Spacer()
                Toggle("", isOn: $settings.showDockIcon)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            Spacer(minLength: 8)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func selectSavePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            settings.savePath = url
        }
    }
}

// MARK: - Layout Helpers

private struct SettingsSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 38)  // アイコン幅に合わせてインデント
    }
}

private struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

private extension Image {
    func settingsIcon() -> some View {
        self
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .frame(width: 18, alignment: .center)
    }
}

private extension Text {
    func settingsLabel() -> some View {
        self
            .font(.system(size: 13))
    }
}
