// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MelonGallery",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "MelonGallery", targets: ["MelonGallery"])
  ],
  targets: [
    .executableTarget(
      name: "MelonGallery",
      resources: [
        .process("Resources")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
