// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ClinicalData",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "ClinicalModels", targets: ["ClinicalModels"]),
        .library(name: "ClinicalPersistence", targets: ["ClinicalPersistence"]),
    ],
    dependencies: [
        // Keep these versions aligned with the app's Package.resolved.
        .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.12.1"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.17.1"),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", exact: "0.39.2"),
    ],
    targets: [
        .target(
            name: "ClinicalModels",
            dependencies: [.product(name: "Dependencies", package: "swift-dependencies")]
        ),
        .target(
            name: "ClinicalPersistence",
            dependencies: [
                "ClinicalModels",
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
            ]
        ),
        .testTarget(
            name: "ClinicalDataTests",
            dependencies: [
                "ClinicalModels", "ClinicalPersistence",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            // Check the public API under the app's default actor isolation.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
