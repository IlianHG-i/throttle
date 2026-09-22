// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RAMBrider",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .executableTarget(
            name: "RAMBrider",
            dependencies: ["CLibProc"],
            path: "Sources/RAMBrider",
            exclude: ["Info.plist"]
        )
    ]
)
