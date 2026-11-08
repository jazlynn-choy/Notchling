// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notchling",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Notchling", targets: ["Notchling"]),
    ],
    targets: [
        // Platform-agnostic logic, state and the protocols that wrap system services.
        .target(name: "NotchlingCore"),
        // SwiftUI views. Depends only on Core, never on AppKit window plumbing.
        .target(name: "NotchlingUI", dependencies: ["NotchlingCore"]),
        // The app: window, mouse tracking and wiring real providers together.
        .executableTarget(name: "Notchling", dependencies: ["NotchlingCore", "NotchlingUI"]),
        .testTarget(name: "NotchlingCoreTests", dependencies: ["NotchlingCore"]),
    ],
    swiftLanguageModes: [.v6]
)
