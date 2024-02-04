
// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "piper-objc",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "piper-objc",
            targets: ["piper-objc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/IhorShevchuk/piper",
                 revision: "d3aa5943bf05b5740f9038186eb6cc93b6283cac"),
    ],
    targets: [
        .target(name: "piper-objc",
                dependencies: [
                    .product(name: "piper", package: "piper")
                ],
                path: "Sources",
                resources: [
                ]
               )
    ],
    cxxLanguageStandard: .cxx17
)
