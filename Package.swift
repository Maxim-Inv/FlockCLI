import PackageDescription

let package = Package(
  name: "FlockCLI",
  dependencies: [
    .Package(url: "/Users/jakeheiser/Documents/Apps/SwiftCLI", majorVersion: 1, minor: 1)
  ]
)
