// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OrcaWatch",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "OrcaWatchCore", targets: ["OrcaWatchCore"]),
    .executable(name: "orca-watch", targets: ["OrcaWatchCLI"]),
  ],
  targets: [
    .target(name: "OrcaWatchCore"),
    .target(name: "OrcaWatchTerminal", dependencies: ["OrcaWatchCore"]),
    .executableTarget(name: "OrcaWatchCLI", dependencies: ["OrcaWatchCore", "OrcaWatchTerminal"]),
    .testTarget(name: "OrcaWatchCoreTests", dependencies: ["OrcaWatchCore"]),
    .testTarget(name: "OrcaWatchTerminalTests", dependencies: ["OrcaWatchTerminal"]),
  ],
  swiftLanguageModes: [.v5]
)
