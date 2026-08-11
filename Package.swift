// swift-tools-version: 6.0

import PackageDescription

/// MediaHub for macOS.
///
/// Deliberately split in two, and the split is not stylistic — it is about what
/// can be *proved*:
///
/// * `MediaHubKit` imports no AppKit, no SwiftUI, no AVFoundation. It is the API
///   client, the models, the subtitle parser and the resume arithmetic — which is
///   where the bugs in a client like this actually live. It compiles and its
///   tests run on Linux, which is where this project is developed, so none of it
///   reaches a Mac unproven.
///
/// * The app target on top of it is views and a player. It needs a Mac to build.
///
/// The previous two clients written for this project were both shipped without
/// ever being run. This layout exists so that cannot happen to the logic again.
let package = Package(
    name: "MediaHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MediaHubKit", targets: ["MediaHubKit"]),
    ],
    targets: [
        .target(
            name: "MediaHubKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MediaHubKitTests",
            dependencies: ["MediaHubKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
