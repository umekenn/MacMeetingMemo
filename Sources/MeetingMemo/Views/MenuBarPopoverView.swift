import SwiftUI
import AppKit

// MARK: - Menu Bar Popover View

struct MenuBarPopoverView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var settings: AppSettings

    var onNewMeeting: () -> Void
    var onResumeSession: (Session) -> Void
    var onOpenSettings: () -> Void

    // アイコン列の固定幅（全行で左端を揃える）
    private let iconWidth: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        // 角丸＋背景色でネイティブメニュー風に見せる
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
        .padding(6) // シャドウが切れないよう余白
        .frame(width: 292)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 15))
                    .frame(width: iconWidth, alignment: .center)
                Text("MacMeetingMemo")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Currently recording indicator
            if session.isRecording {
                recordingIndicator
                Divider()
            }

            // New Meeting button
            Button {
                onNewMeeting()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 15))
                        .frame(width: iconWidth, alignment: .center)
                    Text("新しい会議を開始")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Recent sessions
            if !session.recentSessions.isEmpty {
                Divider()

                Text("最近の会議")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                ForEach(session.recentSessions.prefix(3)) { s in
                    RecentSessionRow(session: s, iconWidth: iconWidth) {
                        onResumeSession(s)
                    }
                }
            }

            Divider()

            // Save path
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .frame(width: iconWidth, alignment: .center)
                Text(settings.savePath.abbreviatingWithTilde)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            Divider()

            // Settings
            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .foregroundColor(.primary)
                        .font(.system(size: 13))
                        .frame(width: iconWidth, alignment: .center)
                    Text("設定")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Quit
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                        .frame(width: iconWidth, alignment: .center)
                    Text("終了")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .frame(width: iconWidth, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("記録中")
                        .font(.system(size: 12, weight: .medium))
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(session.elapsedTimeFormatted)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if let name = session.currentSession?.name, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("停止") {
                session.endSession()
                NSApp.windows.first(where: { $0 is ControlBarPanel })?.orderOut(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Recent Session Row

struct RecentSessionRow: View {
    let session: Session
    var iconWidth: CGFloat = 20
    var onResume: () -> Void

    var body: some View {
        Button {
            onResume()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .frame(width: iconWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(session.startedAt.relativeDescription)
                            .font(.system(size: 12, weight: .medium))
                        Text(session.startedAt.timeString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(session.name.isEmpty ? "無題の会議" : session.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Helpers

extension Date {
    var relativeDescription: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "今日" }
        if cal.isDateInYesterday(self) { return "昨日" }
        let df = DateFormatter()
        df.dateFormat = "M/d"
        return df.string(from: self)
    }

    var timeString: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: self)
    }
}
