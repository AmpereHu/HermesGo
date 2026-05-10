// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HermesMobile",
    defaultLocalization: "zh-Hant",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "HermesMobile",
            targets: ["HermesMobile"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.3.0")
    ],
    targets: [
        .target(
            name: "HermesMobile",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/HermesMobile"
        ),
        .testTarget(
            name: "HermesMobileTests",
            dependencies: ["HermesMobile"],
            path: "Tests/HermesMobileTests"
        )
    ]
)
