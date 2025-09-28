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
                 from: "0.1.1")
    ],
    targets: [
        .target(name: "piper-objc",
                dependencies: [
                    .product(name: "piper1-gpl", package: "piper1-gpl-spm")
                ],
                path: "Sources/piper-objc",
                cxxSettings: [
                    .headerSearchPath("utils")
                ],
                linkerSettings: [
                    .linkedFramework("NaturalLanguage")
                ]
               ),
        .target(name: "piper-player",
                dependencies: [
                    .target(name: "piper-objc")
                ]),
        .executableTarget(
            name: "piper-sample",
            dependencies: [
                .target(name: "piper-player")
            ],
            resources: [
                .copy("resources/model.onnx"),
                .copy("resources/model.onnx.json"),
                .copy("resources/espeak-ng-data")
                
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
