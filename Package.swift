// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "grayscale-auto",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GrayscaleCore", targets: ["GrayscaleCore"]),
        .executable(name: "GrayscaleCoreContractTests", targets: ["GrayscaleCoreContractTests"]),
        .executable(name: "OverlaySpike", targets: ["OverlaySpike"]),
        .executable(name: "grayscale-auto", targets: ["GrayscaleAuto"]),
    ],
    targets: [
        .target(
            name: "GrayscaleCore",
            dependencies: ["CPrivateAPIs"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .target(
            name: "CPrivateAPIs",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        .executableTarget(
            name: "GrayscaleCoreContractTests",
            dependencies: ["GrayscaleCore"]
        ),
        .executableTarget(
            name: "OverlaySpike",
            dependencies: ["GrayscaleCore"]
        ),
        .executableTarget(
            name: "GrayscaleAuto",
            dependencies: ["GrayscaleCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
