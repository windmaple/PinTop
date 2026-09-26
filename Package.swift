// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinTop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PinTop", targets: ["PinTop"])
    ],
    targets: [
        .executableTarget(
            name: "PinTop",
            path: "Sources/PinTop",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
