import RealityKit
import simd

// MARK: - Toon / cel shading components
//
// A cel-shaded look (quantized N.L bands) plus a black inverted-hull outline,
// applied per entity through a component and driven by `ToonShadingManager`.
//
// visionOS RealityKit does not expose scene lights to a material graph, so the
// key light is baked into the shader as a constant direction. The outline is a
// duplicated mesh, scaled outward, rendered with front-face culling so only the
// back faces (the black hull) remain visible behind the real mesh.

/// How a flagged entity should be styled.
public enum ToonMode: Equatable, Sendable {
    /// Cel-shaded body material + outline.
    case full
    /// Keep the existing material, add the outline only.
    case outlineOnly
}

/// Flags an entity (and its descendants) for toon styling.
public struct ToonShadedComponent: Component {
    /// Cel body tint, linear RGB 0...1. Ignored in `.outlineOnly`.
    public var baseColor: SIMD3<Float>
    public var mode: ToonMode
    /// Outline tint, linear RGB 0...1.
    public var outlineColor: SIMD3<Float>
    /// Uniform expansion of the outline hull (1.0 = no outline).
    public var outlineScale: Float
    /// Number of shading bands for the cel ramp.
    public var bands: Float
    /// Set once styling has been applied so re-entry is cheap.
    public var applied: Bool

    public init(baseColor: SIMD3<Float> = [0.78, 0.78, 0.80],
                mode: ToonMode = .full,
                outlineColor: SIMD3<Float> = [0, 0, 0],
                outlineScale: Float = 1.045,
                bands: Float = 3,
                applied: Bool = false) {
        self.baseColor = baseColor
        self.mode = mode
        self.outlineColor = outlineColor
        self.outlineScale = outlineScale
        self.bands = bands
        self.applied = applied
    }
}

/// Tags a generated outline-hull child so it is never double-processed.
public struct ToonOutlineComponent: Component {
    public init() {}
}
