// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "ReSwift-Persist",
    platforms: [
        .iOS(.v9)
    ],
    products: [
        .library(name: "ReSwift-Persist", targets: ["ReSwift-Persist"]),
    ],
    dependencies: [
        
        .package(name: "RxSwift", path: "../RxSwift"),
        .package(name: "ReSwift", url: "https://github.com/ReSwift/ReSwift.git", .exact("5.0.0"))
        
//        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "6.0.0")),
//        spec.dependency "ReSwift", "~> 4.1.1"
//        spec.dependency "RxSwift", "5.1.1"
    ],
    targets: [
        .target(name: "ReSwift-Persist", dependencies: ["RxSwift", "ReSwift"], path: "ReSwift-Persist/Source")
    ]
)
