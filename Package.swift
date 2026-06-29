// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HayStack",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "HayStack",
            dependencies: ["HotKey"],
            path: "HayStack",
            exclude: [
                "Info.plist",
                "HayStack.entitlements",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
