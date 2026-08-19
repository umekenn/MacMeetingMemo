// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMeetingMemo",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MeetingMemo",
            path: "Sources/MeetingMemo",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
