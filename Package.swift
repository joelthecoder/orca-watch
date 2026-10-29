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
    .executableTarget(name: "OrcaWatchCLI", dependencies: ["OrcaWatchCore"]),
    .testTarget(name: "OrcaWatchCoreTests", dependencies: ["OrcaWatchCore"]),
  ],
  swiftLanguageModes: [.v5]
)
