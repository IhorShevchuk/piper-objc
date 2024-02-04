
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
        .package(url: "https://github.com/IhorShevchuk/espeak-ng-spm",
                 revision: "15b87671e3c7486b6a4404f997b1ae59a7eae441"),
        .package(url: "https://github.com/IhorShevchuk/piper",
                 revision: "84035c399351719f14d2f99e477590dd333dcb54"),
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
