import SwiftUI
import DicyaninToonShader

/// A tiny volumetric visionOS app that shows the DicyaninToonShader Metal /
/// ShaderGraph looks applied live to a turntable of cubes and low-poly props.
///
/// The props are recreations of the flat-matte "low poly" vocabulary from the
/// VisionSocial build catalog (tree, mushroom, crate, barrel, crystal, gem,
/// lantern, flower, rock, pine) so the cel ramp + inverted-hull outline have
/// real silhouettes to bite into, not just boxes.
@main
struct ToonShaderDemoApp: App {

    init() {
        // Toon components + the turntable system must be registered once, at
        // launch, before any scene is built.
        ToonShadingManager.registerComponents()
        TurntableComponent.registerComponent()
        TurntableSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // A true 3D preview volume the user can walk around and inspect from
        // any angle — the best way to read a baked-light cel shader.
        .windowStyle(.volumetric)
        .defaultSize(width: 0.9, height: 0.7, depth: 0.9, in: .meters)
    }
}
