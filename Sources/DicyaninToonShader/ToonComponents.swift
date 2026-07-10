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
    /// Unlit wireframe rendering (triangle edges only), no outline hull.
    case wireframe
    /// Enviro-Bear 2000 style: garish MS-Paint flat colours picked from a
    /// clashing palette, harsh 2-band shading, noisy scribble splotches, and a
    /// thick wobbly dark-brown outline. `baseColor` is ignored — the palette
    /// colour is chosen deterministically per entity.
    case envirobear
    /// 1950s–60s pop-art comic: hard 2-band cel with Ben-Day halftone dots
    /// filling the shadow side, plus a thick black ink outline. Uses `baseColor`.
    case popArt
    /// 1960s psychedelic poster: animated rainbow hue bands flowing across the
    /// surface, quantized hard so it stays graphic. `baseColor` is ignored.
    case psychedelic
    /// 1980s synthwave: near-black indigo body, quantized neon fresnel rim
    /// (colour picked per entity from a neon palette), animated scanlines, and
    /// a matching neon outline. `baseColor` is ignored.
    case synthwave
    /// 1990s Game Boy DMG-01: the authentic 4-shade green LCD palette with a
    /// darkest-green outline. `baseColor` is ignored — that's the point.
    case gameboy
    /// 2000s Y2K liquid chrome: banded iridescent fresnel with a slowly
    /// drifting hue and hot specular pings. `baseColor` is ignored.
    case y2kChrome
    /// 1930s rubber-hose cartoon (Steamboat Willie): 2-band grayscale, dancing
    /// film grain, projector brightness flicker, and a faint sepia fade, with a
    /// thick ink outline. `baseColor` is ignored — it's a black-and-white film.
    case rubberHose
    /// 1970s velvet blacklight poster: near-black felt body with fluorescent
    /// contour bands that slowly pulse like UV paint under a blacklight. The
    /// fluoro colour is picked per entity from a dayglo palette; `baseColor`
    /// is ignored.
    case blacklight
    /// 1987 Predator thermal vision: hard-quantized heat ramp (deep blue →
    /// purple → red → orange → white-hot) driven by lighting + fresnel, with
    /// slowly drifting hot spots. `baseColor` is ignored.
    case thermal
    /// 1990s worn VHS tape: cel shading with RGB channel mis-registration
    /// (colour fringing along the silhouette) and a rolling tracking-noise bar.
    /// Uses `baseColor` for the body tint.
    case vhs
    /// 2010s sci-fi hologram: translucent-looking cyan projection built from
    /// horizontal slices, global flicker, and glitch bands that skip sideways.
    /// `baseColor` is ignored.
    case hologram
    /// 1940s film noir: brutal 2-band black-and-white with hard venetian-blind
    /// slat shadows creeping across every surface and dancing silver grain.
    /// `baseColor` is ignored — it's always shot in black and white.
    case filmNoir
    /// 1985 "Take On Me" pencil sketch: warm paper white with graphite
    /// cross-hatching that fills in as surfaces turn from the light, boiling
    /// at 8 fps like hand-redrawn animation. `baseColor` is ignored.
    case sketch
    /// 1980s arcade cabinet CRT: the body colour is rendered through vertical
    /// RGB phosphor triad stripes with horizontal scanlines and a rolling
    /// refresh band. Uses `baseColor`.
    case arcade
    /// 1999 Matrix digital rain: near-black body with columns of phosphor-green
    /// code streaming downward, hot white leading glyphs, and a green fresnel
    /// rim. `baseColor` is ignored.
    case matrixRain
    /// 1950s drafting-room blueprint: cyanotype blue paper with white contour
    /// lines at every shading terminator, a faint graph-paper grid, and bright
    /// silhouette linework. `baseColor` is ignored.
    case blueprint
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

/// Excludes an entity and its entire subtree from toon styling. Put this on
/// skyboxes, lights, UI, or anything that should keep its original material.
public struct ToonIgnoreComponent: Component {
    public init() {}
}
