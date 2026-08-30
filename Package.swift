// swift-tools-version: 5.9
//
//  Package.swift
//  AnisetteKit
//
//  Created by Magesh K on 20/07/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "AnisetteKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AnisetteKit",
            targets: ["AnisetteKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "4.0.0" ..< "5.0.0")
    ],
    targets: [
        .target(
            name: "anisette_core",
            dependencies: [
                .target(name: "Unicorn", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS]))
            ],
            path: "Native",
            cSettings: [
                .headerSearchPath(".")
            ],
            linkerSettings: [
                .linkedLibrary("unicorn", .when(platforms: [.linux, .android]))
            ]
        ),
        .binaryTarget(
            name: "Unicorn",
            url: "https://github.com/mahee96/unicorn/releases/download/2.1.4-xcf-37ffdfb1/Unicorn.xcframework.zip",
            checksum: "4158de08c5979a80a9c4d54c47fd8fdbde0a87ca0e16b1a3deba1ecfadcbd17b"
        ),
        .target(
            name: "AnisetteKit",
            dependencies: [
                "anisette_core",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: ".",
            exclude: [
                "Package.swift",
                "Native", 
                "Tests"
            ],
            sources: ["Sources"]
        ),
        .testTarget(
            name: "AnisetteKitTests",
            dependencies: [
                "AnisetteKit"
            ],
            path: "Tests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
