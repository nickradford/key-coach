// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShortcutCoach",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CoachCore"),
        .executableTarget(name: "ShortcutCoach", dependencies: ["CoachCore"]),
        .testTarget(
            name: "CoachCoreTests",
            dependencies: ["CoachCore"],
            // Command Line Tools without Xcode: the build does not find the Swift Testing macro plugin by itself.
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
    ]
)
