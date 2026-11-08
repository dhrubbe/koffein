// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Koffein",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Koffein", targets: ["Koffein"])],
    targets: [.executableTarget(name: "Koffein")]
)
