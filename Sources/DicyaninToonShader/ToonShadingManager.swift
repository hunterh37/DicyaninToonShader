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

            if settings.mode == .full, let cel = await celMaterial(bands: settings.bands,
                                                                    color: settings.baseColor) {
                model.materials = Array(repeating: cel, count: max(model.materials.count, 1))
                entity.components.set(model)
            }

            addOutline(to: entity, mesh: model.mesh, settings: settings)
        }

        for child in entity.children {
            await styleModels(of: child, settings: settings)
        }
    }

    private func addOutline(to entity: Entity, mesh: MeshResource, settings: ToonShadedComponent) {
        guard settings.outlineScale > 1.0 else { return }
        for child in entity.children where child.components[ToonOutlineComponent.self] != nil {
            child.removeFromParent()
        }

        var hullMat = UnlitMaterial(color: platformColor(settings.outlineColor))
        hullMat.faceCulling = .front

        let hull = ModelEntity(mesh: mesh, materials: [hullMat])
        hull.scale = SIMD3<Float>(repeating: settings.outlineScale)
        hull.components.set(ToonOutlineComponent())
        entity.addChild(hull)
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
