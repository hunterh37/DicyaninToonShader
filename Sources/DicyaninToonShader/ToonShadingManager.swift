import RealityKit
import ShaderGraphCoder
import simd
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Drives cel-shading + outline styling across an entity hierarchy.
///
/// Apply to a whole scene by flagging entities with `ToonShadedComponent` and
/// calling `applyToHierarchy(_:)`, or style a single entity with `style(_:...)`.
@MainActor
public final class ToonShadingManager {

    public static let shared = ToonShadingManager()
    public init() {}

    /// Cached cel material keyed by quantized band count. The body colour is a
    /// shader parameter, so one compiled graph per band count serves every tint.
    private var celCache: [Int: ShaderGraphMaterial] = [:]

    /// Cached Enviro-Bear material; colour is a shader parameter so one graph
    /// serves the whole palette.
    private var envirobearCache: ShaderGraphMaterial?

    /// Register the toon components. Call once at app launch.
    public static func registerComponents() {
        ToonShadedComponent.registerComponent()
        ToonOutlineComponent.registerComponent()
        ToonIgnoreComponent.registerComponent()
    }

    /// True when an entity (or a generated hull) must be skipped during traversal.
    private func skip(_ entity: Entity) -> Bool {
        entity.components[ToonOutlineComponent.self] != nil ||
        entity.components[ToonIgnoreComponent.self] != nil
    }

    // MARK: Public entry points

    /// Flag every mesh-bearing entity in a hierarchy (skipping generated outline
    /// hulls) with a `ToonShadedComponent`, then style the whole scene. This is
    /// the one-call entry point for "toon shade everything under this root".
    public func applyToScene(_ root: Entity,
                             baseColor: SIMD3<Float> = [0.78, 0.78, 0.80],
                             mode: ToonMode = .full,
                             outlineColor: SIMD3<Float> = [0, 0, 0],
                             outlineScale: Float = 1.045,
                             bands: Float = 3) async {
        tagModels(root,
                  baseColor: baseColor,
                  mode: mode,
                  outlineColor: outlineColor,
                  outlineScale: outlineScale,
                  bands: bands)
        await walk(root)
    }

    /// Apply toon styling to every entity in a hierarchy that carries a
    /// `ToonShadedComponent`. Call once after a scene is built.
    public func applyToHierarchy(_ root: Entity) async {
        await walk(root)
    }

    private func tagModels(_ entity: Entity,
                           baseColor: SIMD3<Float>,
                           mode: ToonMode,
                           outlineColor: SIMD3<Float>,
                           outlineScale: Float,
                           bands: Float) {
        if skip(entity) { return }
        if entity.components[ModelComponent.self] != nil,
           entity.components[ToonShadedComponent.self] == nil {
            entity.components.set(ToonShadedComponent(baseColor: baseColor,
                                                      mode: mode,
                                                      outlineColor: outlineColor,
                                                      outlineScale: outlineScale,
                                                      bands: bands))
        }
        for child in entity.children {
            tagModels(child,
                      baseColor: baseColor,
                      mode: mode,
                      outlineColor: outlineColor,
                      outlineScale: outlineScale,
                      bands: bands)
        }
    }

    /// Apply toon styling to a single entity with explicit settings, adding the
    /// component if missing.
    public func style(_ entity: Entity,
                      baseColor: SIMD3<Float> = [0.78, 0.78, 0.80],
                      mode: ToonMode = .full,
                      outlineColor: SIMD3<Float> = [0, 0, 0],
                      outlineScale: Float = 1.045,
                      bands: Float = 3) async {
        var c = entity.components[ToonShadedComponent.self] ?? ToonShadedComponent()
        c.baseColor = baseColor
        c.mode = mode
        c.outlineColor = outlineColor
        c.outlineScale = outlineScale
        c.bands = bands
        c.applied = false
        entity.components.set(c)
        await apply(to: entity, settings: c)
    }

    /// Remove generated outline hulls and clear toon flags from a hierarchy.
    /// Body materials swapped to the cel shader remain until rebuilt.
    public func remove(from entity: Entity) {
        for child in entity.children {
            if child.components[ToonOutlineComponent.self] != nil {
                child.removeFromParent()
            } else {
                remove(from: child)
            }
        }
        entity.components.remove(ToonShadedComponent.self)
    }

    // MARK: Internals

    private func walk(_ entity: Entity) async {
        if skip(entity) { return }
        if var c = entity.components[ToonShadedComponent.self], !c.applied {
            await apply(to: entity, settings: c)
            c.applied = true
            entity.components.set(c)
        }
        for child in entity.children {
            await walk(child)
        }
    }

    private func apply(to entity: Entity, settings: ToonShadedComponent) async {
        await styleModels(of: entity, settings: settings)
    }

    private func styleModels(of entity: Entity, settings: ToonShadedComponent) async {
        if skip(entity) { return }
        if var model = entity.components[ModelComponent.self] {

            switch settings.mode {
            case .full:
                if let cel = await celMaterial(bands: settings.bands,
                                               color: settings.baseColor) {
                    model.materials = Array(repeating: cel, count: max(model.materials.count, 1))
                    entity.components.set(model)
                }
                addOutline(to: entity, mesh: model.mesh, settings: settings)

            case .outlineOnly:
                addOutline(to: entity, mesh: model.mesh, settings: settings)

            case .wireframe:
                var wire = UnlitMaterial(color: platformColor(settings.baseColor))
                wire.triangleFillMode = .lines
                model.materials = Array(repeating: wire, count: max(model.materials.count, 1))
                entity.components.set(model)
                // No outline hull — it would just add more wire clutter.
                for child in entity.children where child.components[ToonOutlineComponent.self] != nil {
                    child.removeFromParent()
                }

            case .envirobear:
                if let mat = await envirobearMaterial(color: Self.envirobearColor(for: entity)) {
                    model.materials = Array(repeating: mat, count: max(model.materials.count, 1))
                    entity.components.set(model)
                }
                // Thick wobbly dark-brown MS-Paint outline, overriding the
                // component's outline settings for maximum crayon energy.
                var s = settings
                s.outlineColor = [0.16, 0.08, 0.03]
                s.outlineScale = max(settings.outlineScale, 1.08)
                addOutline(to: entity, mesh: model.mesh, settings: s, wobble: true)
            }
        }

        for child in entity.children {
            await styleModels(of: child, settings: settings)
        }
    }

    private func addOutline(to entity: Entity, mesh: MeshResource,
                            settings: ToonShadedComponent, wobble: Bool = false) {
        guard settings.outlineScale > 1.0 else { return }
        for child in entity.children where child.components[ToonOutlineComponent.self] != nil {
            child.removeFromParent()
        }

        var hullMat = UnlitMaterial(color: platformColor(settings.outlineColor))
        hullMat.faceCulling = .front

        let hull = ModelEntity(mesh: mesh, materials: [hullMat])
        if wobble {
            // Non-uniform scale so the hull reads like a hand-drawn line whose
            // thickness drifts around the silhouette, seeded per entity.
            let h = Self.hash(entity)
            let extra = settings.outlineScale - 1.0
            func axis(_ salt: UInt64) -> Float {
                1.0 + extra * (0.7 + 0.6 * Float((h ^ salt) % 1000) / 1000.0)
            }
            hull.scale = [axis(0x9E37), axis(0x79B9), axis(0xC2B2)]
        } else {
            hull.scale = SIMD3<Float>(repeating: settings.outlineScale)
        }
        hull.components.set(ToonOutlineComponent())
        entity.addChild(hull)
    }

    // MARK: Enviro-Bear helpers

    /// Clashing MS-Paint bucket-fill palette.
    private static let envirobearPalette: [SIMD3<Float>] = [
        [0.58, 0.32, 0.10], // bear brown
        [1.00, 0.00, 0.00], // pure red
        [0.10, 0.85, 0.10], // pine green
        [1.00, 0.90, 0.00], // hazard yellow
        [1.00, 0.45, 0.00], // traffic-cone orange
        [0.95, 0.20, 0.85], // impossible magenta
        [0.10, 0.55, 1.00], // paint-bucket blue
        [0.45, 0.90, 0.95], // ice cyan
    ]

    private static func hash(_ entity: Entity) -> UInt64 {
        var h = UInt64(entity.id) &* 0x9E3779B97F4A7C15
        h ^= h >> 29; h &*= 0xBF58476D1CE4E5B9
        h ^= h >> 32
        return h
    }

    /// Deterministic garish palette pick per entity.
    static func envirobearColor(for entity: Entity) -> SIMD3<Float> {
        envirobearPalette[Int(hash(entity) % UInt64(envirobearPalette.count))]
    }

    private func envirobearMaterial(color: SIMD3<Float>) async -> ShaderGraphMaterial? {
        if var cached = envirobearCache {
            try? cached.setParameter(name: "BaseColor", value: .color(cgColor(color)))
            return cached
        }
        do {
            var mat = try await ToonMaterialFactory.envirobearMaterial()
            envirobearCache = mat
            try? mat.setParameter(name: "BaseColor", value: .color(cgColor(color)))
            return mat
        } catch {
            return nil
        }
    }

    private func celMaterial(bands: Float, color: SIMD3<Float>) async -> ShaderGraphMaterial? {
        let key = Int(bands.rounded())
        if var cached = celCache[key] {
            try? cached.setParameter(name: "BaseColor", value: .color(cgColor(color)))
            return cached
        }
        do {
            var mat = try await ToonMaterialFactory.celMaterial(bands: Float(key))
            celCache[key] = mat
            try? mat.setParameter(name: "BaseColor", value: .color(cgColor(color)))
            return mat
        } catch {
            return nil
        }
    }

    // MARK: Colour helpers

    private func cgColor(_ c: SIMD3<Float>) -> CGColor {
        CGColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    #if canImport(UIKit)
    private func platformColor(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
    #elseif canImport(AppKit)
    private func platformColor(_ c: SIMD3<Float>) -> NSColor {
        NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
    #endif
}
