// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MelonGallery",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "MelonGallery", targets: ["MelonGallery"]),
    .executable(name: "MelonRAWDecoder", targets: ["MelonRAWDecoder"])
  ],
  targets: [
    .target(name: "RAWImageTransfer"),
    .executableTarget(name: "MelonRAWDecoder", dependencies: ["RAWImageTransfer"]),
    .executableTarget(
      name: "MelonGallery",
      dependencies: ["RAWImageTransfer"],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(name: "MelonGalleryTests", dependencies: ["MelonGallery", "MelonRAWDecoder", "RAWImageTransfer"])
  ],
  swiftLanguageModes: [.v6]
)
