import RealityKit
import UIKit
import simd
import DicyaninToonShader

/// Low-poly prop catalog for the demo, recreated from the VisionSocial
/// `BuildShape` vocabulary: a handful of flat-matte primitive helpers plus
/// prefabs assembled from them. Every prop returns a single entity whose origin
/// sits at its floor point, so placing one is just a position + uniform scale.
///
/// Materials here are cheap `SimpleMaterial`s — `ToonShadingManager` replaces
/// them with the cel / decade ShaderGraph material at apply time, so the colour
/// you set is only what shows through in the untouched `.outlineOnly` mode.
@MainActor
enum DemoProps {

    // MARK: - Palette (from VisionSocial's flat matte scheme)

    static let stone    = UIColor(red: 0.62, green: 0.63, blue: 0.66, alpha: 1)
    static let wood     = UIColor(red: 0.62, green: 0.44, blue: 0.28, alpha: 1)
    static let darkWood = UIColor(red: 0.42, green: 0.29, blue: 0.18, alpha: 1)
    static let leaf     = UIColor(red: 0.36, green: 0.62, blue: 0.36, alpha: 1)
    static let deepLeaf = UIColor(red: 0.24, green: 0.48, blue: 0.30, alpha: 1)
    static let metal    = UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1)
    static let paper    = UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1)
    static let ember    = UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1)
    static let sky      = UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1)
    static let jewel    = UIColor(red: 0.42, green: 0.78, blue: 0.90, alpha: 1)
    static let gold     = UIColor(red: 0.95, green: 0.78, blue: 0.32, alpha: 1)

    // MARK: - Primitive helpers

    static func matte(_ color: UIColor, roughness: Float = 0.85) -> RealityKit.Material {
        SimpleMaterial(color: color, roughness: MaterialScalarParameter(floatLiteral: roughness), isMetallic: false)
    }
    static func glow(_ color: UIColor) -> RealityKit.Material { UnlitMaterial(color: color) }

    static func box(_ size: SIMD3<Float>, _ m: RealityKit.Material, corner: Float = 0.01) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(corner, size.min() * 0.3)), materials: [m])
    }
    static func cyl(height: Float, radius: Float, _ m: RealityKit.Material) -> ModelEntity {
        ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [m])
    }
    static func cone(height: Float, radius: Float, _ m: RealityKit.Material) -> ModelEntity {
        ModelEntity(mesh: .generateCone(height: height, radius: radius), materials: [m])
    }
    static func ball(_ radius: Float, _ m: RealityKit.Material) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius), materials: [m])
    }

    // MARK: - Props

    static func tree() -> Entity {
        let root = Entity()
        let trunk = cyl(height: 0.7, radius: 0.09, matte(darkWood))
        trunk.position = [0, 0.35, 0]
        root.addChild(trunk)
        let puffs: [(SIMD3<Float>, Float)] = [
            ([0, 1.0, 0], 0.32), ([0.2, 0.85, 0.05], 0.2),
            ([-0.18, 0.88, -0.06], 0.22), ([0.05, 0.78, -0.18], 0.18),
        ]
        for (p, r) in puffs { let leaf = ball(r, matte(Self.leaf)); leaf.position = p; root.addChild(leaf) }
        return root
    }

    static func pine() -> Entity {
        let root = Entity()
        let trunk = cyl(height: 0.4, radius: 0.08, matte(darkWood))
        trunk.position = [0, 0.2, 0]
        root.addChild(trunk)
        for i in 0..<3 {
            let tier = cone(height: 0.5, radius: 0.36 - Float(i) * 0.09, matte(deepLeaf))
            tier.position = [0, 0.5 + Float(i) * 0.34, 0]
            root.addChild(tier)
        }
        return root
    }

    static func mushroom() -> Entity {
        let root = Entity()
        let stem = cyl(height: 0.3, radius: 0.06, matte(paper))
        stem.position = [0, 0.15, 0]
        root.addChild(stem)
        let cap = ball(0.17, matte(UIColor(red: 0.85, green: 0.3, blue: 0.28, alpha: 1)))
        cap.scale = [1, 0.7, 1]
        cap.position = [0, 0.34, 0]
        root.addChild(cap)
        let spots: [SIMD3<Float>] = [[0.06, 0.4, 0.02], [-0.05, 0.41, 0.05], [0.02, 0.42, -0.07], [-0.07, 0.39, -0.04]]
        for p in spots { let dot = ball(0.025, matte(paper)); dot.position = p; root.addChild(dot) }
        return root
    }

    static func rock() -> Entity {
        let root = Entity()
        let chunks: [(SIMD3<Float>, Float)] = [([0, 0.16, 0], 0.24), ([0.18, 0.1, 0.06], 0.15), ([-0.16, 0.09, -0.08], 0.14)]
        for (p, r) in chunks {
            let c = ball(r, matte(stone)); c.position = p; c.scale = [1.0, 0.8, 1.0]; root.addChild(c)
        }
        return root
    }

    static func flower() -> Entity {
        let root = Entity()
        let stem = cyl(height: 0.42, radius: 0.02, matte(deepLeaf))
        stem.position = [0, 0.21, 0]
        root.addChild(stem)
        let center = ball(0.06, matte(gold))
        center.position = [0, 0.46, 0]
        root.addChild(center)
        for i in 0..<6 {
            let a = Float(i) / 6 * 2 * .pi
            let petal = ball(0.05, matte(UIColor(red: 0.95, green: 0.5, blue: 0.6, alpha: 1)))
            petal.position = [cos(a) * 0.1, 0.46, sin(a) * 0.1]
            petal.scale = [1.3, 0.5, 1.3]
            root.addChild(petal)
        }
        return root
    }

    static func crate() -> Entity {
        let root = Entity()
        let body = box([0.45, 0.45, 0.45], matte(wood), corner: 0.01)
        body.position = [0, 0.225, 0]
        root.addChild(body)
        for z: Float in [0.23, -0.23] {
            let plank = box([0.47, 0.06, 0.02], matte(darkWood))
            plank.position = [0, 0.225, z]
            root.addChild(plank)
        }
        let cross = box([0.47, 0.06, 0.02], matte(darkWood))
        cross.position = [0, 0.225, 0.23]
        cross.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])
        root.addChild(cross)
        return root
    }

    static func barrel() -> Entity {
        let root = Entity()
        let body = cyl(height: 0.55, radius: 0.2, matte(wood))
        body.position = [0, 0.275, 0]
        root.addChild(body)
        for y: Float in [0.12, 0.42] {
            let band = cyl(height: 0.05, radius: 0.205, matte(metal))
            band.position = [0, y, 0]
            root.addChild(band)
        }
        return root
    }

    static func lantern() -> Entity {
        let root = Entity()
        let post = cyl(height: 0.5, radius: 0.03, matte(metal))
        post.position = [0, 0.25, 0]
        root.addChild(post)
        let cage = box([0.2, 0.24, 0.2], matte(metal), corner: 0.02)
        cage.position = [0, 0.6, 0]
        root.addChild(cage)
        let light = box([0.13, 0.17, 0.13], glow(UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1)))
        light.position = [0, 0.6, 0]
        // The glowing pane keeps its unlit look — exclude it from toon styling.
        light.components.set(ToonIgnoreComponent())
        root.addChild(light)
        let top = cone(height: 0.1, radius: 0.14, matte(metal))
        top.position = [0, 0.77, 0]
        root.addChild(top)
        return root
    }

    static func crystal() -> Entity {
        let root = Entity()
        let base = box([0.2, 0.05, 0.2], matte(stone), corner: 0.01)
        base.position = [0, 0.025, 0]
        root.addChild(base)
        let shards: [(SIMD3<Float>, Float, Float)] = [
            ([0, 0, 0], 0.32, 0.05), ([0.06, 0.02, 0.04], 0.22, 0.04), ([-0.05, 0.01, -0.03], 0.26, 0.045),
        ]
        for (p, h, r) in shards {
            let shard = cone(height: h, radius: r, matte(jewel, roughness: 0.15))
            shard.position = [p.x, 0.05 + h / 2, p.z]
            root.addChild(shard)
        }
        return root
    }

    static func gem() -> Entity {
        let root = Entity()
        let top = cone(height: 0.3, radius: 0.17, matte(jewel, roughness: 0.15))
        top.position = [0, 0.3, 0]
        root.addChild(top)
        let bottom = cone(height: 0.2, radius: 0.17, matte(jewel, roughness: 0.15))
        bottom.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        bottom.position = [0, 0.1, 0]
        root.addChild(bottom)
        return root
    }

    /// A plain cube — the simplest thing to read the cel ramp + outline on.
    static func cube(_ color: UIColor) -> Entity {
        let root = Entity()
        let c = box([0.34, 0.34, 0.34], matte(color), corner: 0.015)
        c.position = [0, 0.17, 0]
        root.addChild(c)
        return root
    }
}
