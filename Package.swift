// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetRadioMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NetRadio", targets: ["NetRadioMac"])],
    targets: [.executableTarget(name: "NetRadioMac")]
)
