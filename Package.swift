// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SwitchTool", platforms: [.macOS(.v13)], products: [
    .executable(name: "SwitchTool", targets: ["SwitchTool"]),
    .executable(name: "SwitchHelper", targets: ["SwitchHelper"])
], targets: [
    .target(name: "SMCBridge", linkerSettings: [.linkedFramework("IOKit")]),
    .target(name: "PowerCore", dependencies: ["SMCBridge"], linkerSettings: [.linkedFramework("IOKit")]),
    .executableTarget(name: "SwitchHelper", dependencies: ["PowerCore"]),
    .executableTarget(name: "SwitchTool", dependencies: ["PowerCore"]),
    .testTarget(name: "PowerCoreTests", dependencies: ["PowerCore"])
])
