// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DicyaninToonShader",
    platforms: [
        .visionOS(.v2),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "DicyaninToonShader",
            targets: ["DicyaninToonShader"]
        )
    ],
    dependencies: [
        .package(path: "../ShaderGraphCoder")
    ],
    targets: [
        .target(
            name: "DicyaninToonShader",
            dependencies: ["ShaderGraphCoder"]
        ),
        .testTarget(
            name: "DicyaninToonShaderTests",
            dependencies: ["DicyaninToonShader"]
        )
    ]
)
