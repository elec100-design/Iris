// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SafetyLegalRAG",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SafetyLegalRAG",
            targets: ["SafetyLegalRAG"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "SafetyLegalRAG",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/SafetyLegalRAG"
        ),
        .testTarget(
            name: "SafetyLegalRAGTests",
            dependencies: ["SafetyLegalRAG"],
            path: "Tests/SafetyLegalRAGTests"
        )
    ]
)
