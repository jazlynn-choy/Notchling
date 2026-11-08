// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notchling",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Notchling", targets: ["Notchling"]),
        .executable(name: "notch", targets: ["notch"]),
    ],
    targets: [
        // The activity format shared by the app and the `notch` command. Foundation only,
        // so the command stays tiny and starts instantly.
        .target(name: "NotchlingActivity"),
        // Platform-agnostic logic, state and the protocols that wrap system services.
        .target(name: "NotchlingCore", dependencies: ["NotchlingActivity"]),
        // SwiftUI views. Depends only on Core, never on AppKit window plumbing.
        .target(name: "NotchlingUI", dependencies: ["NotchlingCore", "NotchlingActivity"]),
        // `notch`: shows a terminal command's progress in the notch.
        .executableTarget(name: "notch", dependencies: ["NotchlingActivity"]),
        // The app: window, mouse tracking and wiring real providers together.
        .executableTarget(name: "Notchling", dependencies: ["NotchlingCore", "NotchlingUI"]),
        .testTarget(name: "NotchlingCoreTests", dependencies: ["NotchlingCore", "NotchlingActivity"]),
    ],
    swiftLanguageModes: [.v6]
)
