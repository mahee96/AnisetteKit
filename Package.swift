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
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"),
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
                .linkedLibrary("unicorn", .when(platforms: [.linux, .android, .windows]))
            ]
        ),
        .binaryTarget(
            name: "Unicorn",
            url: "https://github.com/mahee96/unicorn/releases/download/2.1.4-multiarch/Unicorn.xcframework.zip",
            checksum: "4f61907db6aafc56fb3e336b524d742342312f498bb40739f1da55fb4a24614a"
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
