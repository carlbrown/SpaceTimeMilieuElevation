import PackageDescription

let package = Package(
    name: "SpaceTimeMilieuElevation",
    dependencies: [
        .Package(url: "git@github.com:carlbrown/SpaceTimeMilieuModel.git", majorVersion: 0, minor: 1),
        .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 1),
        .Package(url: "https://github.com/IBM-Swift/HeliumLogger.git", majorVersion: 1),
    ]
)
