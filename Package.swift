
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
                 revision: "e506e5259e177a662f7ec57a2131be9fc63191e6"),
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
