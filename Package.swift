
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
                 revision: "00fda6328dde5694491c01736c235b8a8747f24a"),
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
