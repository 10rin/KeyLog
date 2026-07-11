// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyLog",
    platforms: [
        .macOS(.v14) // SwiftUIを使うためにmacOSバージョンを指定
    ],
    targets: [
        .executableTarget(
            name: "KeyLog",
            dependencies: [])
    ]
)