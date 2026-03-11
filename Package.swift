// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "piper-objc",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "piper-objc",
            targets: [
                "piper-objc"
            ]),
        .library(name: "piper-player",
                 targets: [
                    "piper-player"
                 ])
    ],
    dependencies: [
        .package(url: "https://github.com/IhorShevchuk/piper1-gpl-spm.git",
                 from: "0.1.2"),
        .package(url: "https://github.com/IhorShevchuk/espeak-ng-spm.git",
                     from: "2025.9.17"
                     )
    ],
    targets: [
        .target(name: "piper-objc",
                dependencies: [
                    .product(name: "piper1-gpl", package: "piper1-gpl-spm"),
                    .product(name: "espeak-ng-data", package: "espeak-ng-spm"),
                    .target(name: "piper-ssml"),
                ],
                path: "Sources/piper-objc",
                cxxSettings: [
                    .headerSearchPath("utils"),
                    .unsafeFlags(["-fmodules", "-fcxx-modules"])
                ],
               ),
        .target(name: "piper-ssml"),
        .target(name: "piper-player",
                dependencies: [
                    .target(name: "piper-objc")
                ]),
    ],
    cxxLanguageStandard: .cxx17
)
