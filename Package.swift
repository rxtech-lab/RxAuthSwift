// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RxAuthSwift",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "RxAuthSwift",
            targets: ["RxAuthSwift"]
        ),
        .library(
            name: "RxAuthSwiftUI",
            targets: ["RxAuthSwiftUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/swhitty/SwiftDraw.git", from: "0.29.0"),
    ],
    targets: [
        .target(
            name: "RxAuthSwift",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "RxAuthSwiftUI",
            dependencies: [
                "RxAuthSwift",
                .product(name: "SwiftDraw", package: "SwiftDraw"),
            ]
        ),
        .testTarget(
            name: "RxAuthSwiftTests",
            dependencies: ["RxAuthSwift"]
        ),
    ]
)
