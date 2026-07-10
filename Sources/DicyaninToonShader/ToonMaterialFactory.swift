import RealityKit
import ShaderGraphCoder
import simd

/// Builds the cel-shading `ShaderGraphMaterial` used by `ToonShadingManager`.
public enum ToonMaterialFactory {

    /// Enviro-Bear 2000 look: flat garish colour, harsh 2-band shading with an
    /// almost-black shadow side, plus low-frequency noise "splotches" that
    /// darken patches of the surface like MS-Paint scribble shading.
    ///
    /// The body colour is a `BaseColor` shader parameter so one compiled graph
    /// serves every palette pick.
    public static func envirobearMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let baseColor = SGValue.color3fParameter(name: "BaseColor",
                                                 defaultValue: [0.85, 0.45, 0.10])
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z]) // pre-normalized
        let ndl = max(dot(n, light), SGValue.float(0))

        // Harsh 2-band lit/shadow split.
        let two = SGValue.float(2)
        let lit = clamp(floor(ndl * two + SGValue.float(0.5)) / two, min: 0, max: 1)

        // Hand-scribbled splotches: quantize world-space noise into on/off blobs.
        let noise = (fractal3D(amplitude: SGValue.float(1),
                               octaves: SGValue.int(2),
                               position: SGValue.worldPosition * SGValue.float(6)) as! SGColor).r
        let splotch = clamp(floor(SGValue.float(1.55) - noise),
                            min: 0, max: 1) // 0 inside noisy dark blobs, 1 elsewhere

        // Shadow side is nearly black; splotches darken the lit side too.
        let shadow = mixColor(fg: baseColor, bg: SGValue.color3f([0.02, 0.01, 0.0]),
                              mix: SGValue.float(0.78))
        let shaded = mixColor(fg: baseColor, bg: shadow, mix: lit)
        let final = mixColor(fg: shaded, bg: shadow, mix: splotch)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// Cel ramp: quantize max(N.L, 0) into `bands` steps against a baked key
    /// light, then blend between a darkened shadow tint and the body colour.
    ///
    /// The body colour is exposed as a `BaseColor` shader parameter so a single
    /// compiled graph can be re-tinted per entity via `setParameter`.
    public static func celMaterial(bands: Float,
                                   keyLight: SIMD3<Float> = [0.40, 0.82, 0.41],
                                   shadowMix: Float = 0.42) async throws -> ShaderGraphMaterial {
        let baseColor = SGValue.color3fParameter(name: "BaseColor",
                                                 defaultValue: [0.78, 0.78, 0.80])
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z]) // pre-normalized
        let ndl = max(dot(n, light), SGValue.float(0))

        let b = SGValue.float(bands)
        let stepped = floor(ndl * b + SGValue.float(0.5)) / b
        let lit = clamp(stepped, min: 0, max: 1)

        let shadow = mixColor(fg: baseColor, bg: SGValue.color3f([0, 0, 0]), mix: SGValue.float(shadowMix))
        let shaded = mixColor(fg: baseColor, bg: shadow, mix: lit)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: shaded))
    }

    // MARK: - Decade styles

    /// 1950s–60s pop-art comic (Lichtenstein): hard 2-band cel shading where
    /// the shadow side is filled with Ben-Day halftone dots of a darkened ink
    /// colour instead of a flat tone. Pair with a thick black outline.
    ///
    /// Body colour is a `BaseColor` shader parameter.
    public static func popArtMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41],
                                      dotFrequency: Float = 48) async throws -> ShaderGraphMaterial {
        let baseColor = SGValue.color3fParameter(name: "BaseColor",
                                                 defaultValue: [0.95, 0.15, 0.12])
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))

        // Ben-Day dot grid in world space: distance-to-cell-centre test.
        let p = SGValue.worldPosition * SGValue.float(dotFrequency)
        let gx = fract(p.x) - SGValue.float(0.5)
        let gy = fract(p.y) - SGValue.float(0.5)
        let gz = fract(p.z) - SGValue.float(0.5)
        // Two overlapping axis grids so dots read from any viewing angle.
        let d2a = gx * gx + gy * gy
        let d2b = gy * gy + gz * gz
        let dotMask = clamp(ifGreater(SGValue.float(0.10), d2a, trueResult: 1.0, falseResult: 0.0) +
                            ifGreater(SGValue.float(0.10), d2b, trueResult: 1.0, falseResult: 0.0),
                            min: 0, max: 1)

        // Shadow region: everything below the single hard terminator.
        let inShadow = ifGreater(SGValue.float(0.55), ndl, trueResult: 1.0, falseResult: 0.0)

        // Ink dots: heavily darkened, blue-biased print shadow.
        let ink = mixColor(fg: SGValue.color3f([0.05, 0.02, 0.15]), bg: baseColor,
                           mix: SGValue.float(0.82))
        let final = mixColor(fg: ink, bg: baseColor, mix: inShadow * dotMask)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1960s psychedelic poster / liquid light show: the hue itself is the cel
    /// ramp. Rainbow bands flow across the surface over time, quantized into
    /// hard hue steps so it stays graphic rather than gradient-mushy, with a
    /// 2-band value split from the key light keeping the form readable.
    public static func psychedelicMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41],
                                           speed: Float = 0.10,
                                           hueBands: Float = 6) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let wp = SGValue.worldPosition

        // Swirling hue field: lighting + position + time, snapped to hard bands.
        let hueRaw = fract(ndl * SGValue.float(0.55)
                           + wp.y * SGValue.float(0.45)
                           + sin(wp.x * SGValue.float(2.2) + SGValue.time * SGValue.float(speed * 8)) * SGValue.float(0.12)
                           + SGValue.time * SGValue.float(speed))
        let hue = floor(hueRaw * SGValue.float(hueBands)) / SGValue.float(hueBands)

        // 2-band value split so the shape still shades like a toon.
        let lit = clamp(floor(ndl * SGValue.float(2) + SGValue.float(0.5)) / SGValue.float(2),
                        min: 0, max: 1)
        let value = SGValue.float(0.55) + lit * SGValue.float(0.45)

        let rgb = hsvToRGB(SGValue.color3f(hue, SGValue.float(0.95), value))
        return try await ShaderGraphMaterial(surface: unlitSurface(color: rgb))
    }

    /// 1980s synthwave / retrowave: near-black indigo body, hard-quantized
    /// neon fresnel rim, and animated horizontal scanline glow sweeping up the
    /// mesh. The rim colour is a `RimColor` shader parameter so one graph
    /// serves the whole neon palette.
    public static func synthwaveMaterial() async throws -> ShaderGraphMaterial {
        let rimColor = SGValue.color3fParameter(name: "RimColor",
                                                defaultValue: [1.0, 0.12, 0.75])
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let ndv = abs(dot(n, v))

        // Quantized neon rim: 3 hard glow bands hugging the silhouette.
        let fresnel = clamp(oneMinus(ndv), min: 0, max: 1)
        let rimQ = clamp(floor(pow(fresnel, SGValue.float(2.0)) * SGValue.float(3) + SGValue.float(0.35)) / SGValue.float(3),
                         min: 0, max: 1)

        // Scanlines crawling upward, brightest near the rim like CRT bloom.
        let scan = ifGreater(sin(SGValue.worldPosition.y * SGValue.float(90) - SGValue.time * SGValue.float(2.5)),
                             SGValue.float(0.55), trueResult: 1.0, falseResult: 0.0)

        let body = SGValue.color3f([0.03, 0.01, 0.10])
        let rim = mixColor(fg: rimColor, bg: body, mix: rimQ)
        let final = mixColor(fg: rimColor * SGValue.float(0.55), bg: rim,
                             mix: scan * fresnel * SGValue.float(0.6))

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1990s original Game Boy DMG-01: the authentic 4-shade pea-soup green
    /// LCD palette, hard-quantized from the key light. No parameters — the
    /// whole point is that everything is exactly these four greens.
    public static func gameboyMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))

        // DMG-01 palette, darkest to lightest.
        let g0 = SGValue.color3f([0.06, 0.22, 0.06])
        let g1 = SGValue.color3f([0.19, 0.38, 0.19])
        let g2 = SGValue.color3f([0.55, 0.67, 0.06])
        let g3 = SGValue.color3f([0.61, 0.74, 0.06])

        let q = clamp(floor(ndl * SGValue.float(4)), min: 0, max: 3)
        let final = ifGreater(q, SGValue.float(2.5), trueResult: g3,
                    falseResult: ifGreater(q, SGValue.float(1.5), trueResult: g2,
                    falseResult: ifGreater(q, SGValue.float(0.5), trueResult: g1,
                    falseResult: g0)))

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 2000s Y2K liquid chrome: iridescent fresnel banding whose hue slowly
    /// drifts over time, plus a hot white specular ping when a face points
    /// straight at the viewer. Think chrome wordmark on a flip-phone ad.
    public static func y2kChromeMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let ndv = abs(dot(n, v))
        let fresnel = clamp(oneMinus(ndv), min: 0, max: 1)

        // Iridescent hue wraps around the silhouette and drifts with time.
        let hueRaw = fract(fresnel * SGValue.float(1.3)
                           + n.y * SGValue.float(0.25)
                           + SGValue.time * SGValue.float(0.05))
        let hue = floor(hueRaw * SGValue.float(8)) / SGValue.float(8)

        // 3-band chrome value from the key light, biased bright.
        let lit = clamp(floor(ndl * SGValue.float(3) + SGValue.float(0.5)) / SGValue.float(3),
                        min: 0, max: 1)
        let value = SGValue.float(0.35) + lit * SGValue.float(0.65)

        let irid = hsvToRGB(SGValue.color3f(hue, SGValue.float(0.45), value))

        // Hot white ping on face-on highlights, hard-edged like an airbrush spot.
        let ping = ifGreater(ndv, SGValue.float(0.96), trueResult: 1.0, falseResult: 0.0)
        let final = mixColor(fg: SGValue.color3f([1, 1, 1]), bg: irid, mix: ping)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }
}
