import RealityKit
import UIKit
import simd
import DicyaninToonShader

/// Builds the turntable of demo content and tags each item for toon styling.
///
/// Each prop root is flagged with its own `ToonShadedComponent` carrying a
/// distinct base tint, so `applyToHierarchy` cel-shades every prop in its own
/// colour (decade styles ignore the tint and pick their own palettes). A
/// front row of three cubes gives the cleanest read on the cel ramp + outline.
@MainActor
enum DemoScene {

    private struct Item {
        let name: String
        let make: () -> Entity
        let tint: SIMD3<Float>
        let scale: Float
    }

    static func build(mode: ToonMode,
                      outlineScale: Float,
                      bands: Float) -> Entity {
        let root = Entity()
        root.name = "DemoSceneRoot"

        // Turntable base the props sit on. It spins via TurntableSystem.
        let table = Entity()
        table.name = "Turntable"
        table.components.set(TurntableComponent(speed: 0.3))
        root.addChild(table)

        let plate = DemoProps.cyl(height: 0.03, radius: 0.36, DemoProps.matte(DemoProps.paper, roughness: 0.9))
        plate.position = [0, 0.015, 0]
        plate.components.set(ToonShadedComponent(baseColor: [0.86, 0.84, 0.78],
                                                 mode: mode, outlineScale: outlineScale, bands: bands))
        table.addChild(plate)

        // Ring of low-poly props around the plate.
        let ring: [Item] = [
            Item(name: "tree",     make: DemoProps.tree,     tint: [0.36, 0.62, 0.36], scale: 0.42),
            Item(name: "mushroom", make: DemoProps.mushroom, tint: [0.85, 0.30, 0.28], scale: 0.6),
            Item(name: "crate",    make: DemoProps.crate,    tint: [0.62, 0.44, 0.28], scale: 0.55),
            Item(name: "barrel",   make: DemoProps.barrel,   tint: [0.70, 0.50, 0.30], scale: 0.55),
            Item(name: "crystal",  make: DemoProps.crystal,  tint: [0.42, 0.78, 0.90], scale: 0.7),
            Item(name: "gem",      make: DemoProps.gem,      tint: [0.85, 0.35, 0.75], scale: 0.6),
            Item(name: "lantern",  make: DemoProps.lantern,  tint: [0.55, 0.57, 0.62], scale: 0.5),
            Item(name: "flower",   make: DemoProps.flower,   tint: [0.95, 0.50, 0.60], scale: 0.55),
            Item(name: "rock",     make: DemoProps.rock,     tint: [0.62, 0.63, 0.66], scale: 0.7),
            Item(name: "pine",     make: DemoProps.pine,     tint: [0.24, 0.48, 0.30], scale: 0.42),
        ]
        let radius: Float = 0.24
        for (i, item) in ring.enumerated() {
            let a = Float(i) / Float(ring.count) * 2 * .pi
            let e = item.make()
            e.name = item.name
            e.scale = SIMD3<Float>(repeating: item.scale)
            e.position = [cos(a) * radius, 0.03, sin(a) * radius]
            e.components.set(ToonShadedComponent(baseColor: item.tint, mode: mode,
                                                 outlineScale: outlineScale, bands: bands))
            table.addChild(e)
        }

        // Three static cubes across the front — the reference read for the ramp.
        let cubeTints: [SIMD3<Float>] = [[0.90, 0.30, 0.28], [0.30, 0.55, 0.95], [0.95, 0.78, 0.32]]
        for (i, tint) in cubeTints.enumerated() {
            let c = DemoProps.cube(UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1))
            c.name = "cube\(i)"
            c.scale = SIMD3<Float>(repeating: 0.55)
            c.position = [(Float(i) - 1) * 0.24, 0.0, 0.46]
            c.components.set(ToonShadedComponent(baseColor: tint, mode: mode,
                                                 outlineScale: outlineScale, bands: bands))
            root.addChild(c)
        }

        return root
    }
}
