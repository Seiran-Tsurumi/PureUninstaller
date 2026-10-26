// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PureUninstaller",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PureUninstaller", targets: ["PureUninstaller"])
    ],
    targets: [
        .executableTarget(
            name: "PureUninstaller",
            path: "Sources/PureUninstaller"
        )
    ]
)
