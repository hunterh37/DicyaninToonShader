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

    /// 1930s rubber-hose cartoon: hard 2-band grayscale like inked animation
    /// cels shot on film — dancing grain that re-rolls every frame, a
    /// projector-gate brightness flicker, and a faint warm sepia fade.
    public static func rubberHoseMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))

        // Hard 2-band ink split: paper white vs ink-wash gray.
        let lit = clamp(floor(ndl * SGValue.float(2) + SGValue.float(0.5)) / SGValue.float(2),
                        min: 0, max: 1)
        let value = SGValue.float(0.30) + lit * SGValue.float(0.62)

        // Film grain: high-frequency noise whose sample position jumps each
        // "frame" (stepped time), so the grain dances like real stock.
        let frame = floor(SGValue.time * SGValue.float(12))
        let grainPos = SGValue.worldPosition * SGValue.float(140) + SGValue.vector3f([1, 1, 1]) * frame
        let grain = (fractal3D(amplitude: SGValue.float(1),
                               octaves: SGValue.int(1),
                               position: grainPos) as! SGColor).r
        let speckle = ifGreater(grain, SGValue.float(0.82), trueResult: 1.0, falseResult: 0.0)

        // Projector gate flicker: subtle global brightness wobble.
        let flicker = SGValue.float(0.94) + sin(SGValue.time * SGValue.float(19)) * SGValue.float(0.06)

        let v = clamp(value * flicker + speckle * SGValue.float(0.12), min: 0, max: 1)
        // Faint sepia fade: warm the whites, keep the blacks inky.
        let final = SGValue.color3f(v, v * SGValue.float(0.96), v * SGValue.float(0.86))

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1970s velvet blacklight poster: near-black felt body with hard
    /// fluorescent contour bands that hug the form like dayglo paint, slowly
    /// pulsing as if the UV tube is humming. The fluoro colour is a
    /// `GlowColor` shader parameter so one graph serves the dayglo palette.
    public static func blacklightMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41],
                                          bands: Float = 5) async throws -> ShaderGraphMaterial {
        let glowColor = SGValue.color3fParameter(name: "GlowColor",
                                                 defaultValue: [1.0, 0.35, 0.0])
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let fresnel = clamp(oneMinus(abs(dot(n, v))), min: 0, max: 1)

        // Contour bands: thin dayglo stripes at the cel terminators. A band
        // lights up where the stepped ramp is about to change value.
        let b = SGValue.float(bands)
        let ramp = ndl * b
        let edge = abs(fract(ramp) - SGValue.float(0.5))
        let stripe = ifGreater(SGValue.float(0.12), edge, trueResult: 1.0, falseResult: 0.0)

        // UV-tube hum: slow pulse in the paint's intensity.
        let hum = SGValue.float(0.75) + sin(SGValue.time * SGValue.float(1.6)) * SGValue.float(0.25)

        // Silhouette always glows — the velvet fuzz catching UV.
        let rim = ifGreater(fresnel, SGValue.float(0.62), trueResult: 1.0, falseResult: 0.0)
        let glowAmt = clamp((stripe + rim) * hum, min: 0, max: 1)

        let velvet = SGValue.color3f([0.015, 0.005, 0.04]) // UV-purple black
        let final = mixColor(fg: glowColor, bg: velvet, mix: glowAmt)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1987 Predator thermal vision: a hard-quantized heat ramp — deep blue,
    /// purple, red, orange, white-hot — driven by lighting plus fresnel so
    /// cores read hot and edges cool, with low-frequency hot spots drifting
    /// across the body like shifting body heat.
    public static func thermalMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let ndv = abs(dot(n, v))

        // Heat field: face-on cores hot, grazing edges cool, plus drifting
        // low-frequency blobs so the "body heat" moves.
        let drift = SGValue.worldPosition * SGValue.float(1.4)
                    + SGValue.vector3f([0.3, 0.7, 0.2]) * SGValue.time * SGValue.float(0.25)
        let blob = (fractal3D(amplitude: SGValue.float(1),
                              octaves: SGValue.int(2),
                              position: drift) as! SGColor).r
        let heat = clamp(ndl * SGValue.float(0.45) + ndv * SGValue.float(0.45)
                         + blob * SGValue.float(0.35) - SGValue.float(0.12),
                         min: 0, max: 1)

        // Quantize into 5 hard bands, then pick FLIR palette stops.
        let q = clamp(floor(heat * SGValue.float(5)), min: 0, max: 4)
        let c0 = SGValue.color3f([0.00, 0.01, 0.25]) // cold deep blue
        let c1 = SGValue.color3f([0.30, 0.00, 0.55]) // purple
        let c2 = SGValue.color3f([0.85, 0.05, 0.10]) // red
        let c3 = SGValue.color3f([1.00, 0.55, 0.05]) // orange
        let c4 = SGValue.color3f([1.00, 1.00, 0.90]) // white-hot
        let final = ifGreater(q, SGValue.float(3.5), trueResult: c4,
                    falseResult: ifGreater(q, SGValue.float(2.5), trueResult: c3,
                    falseResult: ifGreater(q, SGValue.float(1.5), trueResult: c2,
                    falseResult: ifGreater(q, SGValue.float(0.5), trueResult: c1,
                    falseResult: c0))))

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1990s worn VHS tape: 3-band cel shading with RGB channel
    /// mis-registration — the red and blue channels bleed past the terminator
    /// in opposite directions like a badly tracked tape — plus a bright
    /// rolling tracking-noise bar climbing the mesh. Body colour is a
    /// `BaseColor` shader parameter.
    public static func vhsMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let baseColor = SGValue.color3fParameter(name: "BaseColor",
                                                 defaultValue: [0.20, 0.55, 0.90])
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))

        // Three cel ramps with offset terminators = channel mis-registration.
        func band(_ shift: Float) -> SGScalar {
            clamp(floor((ndl + SGValue.float(shift)) * SGValue.float(3) + SGValue.float(0.5)) / SGValue.float(3),
                  min: 0, max: 1)
        }
        let litR = band(0.10)   // red bleeds into the shadow
        let litG = band(0.0)
        let litB = band(-0.10)  // blue pulls back, fringing the lit side

        let floorV = SGValue.float(0.22)
        let r = baseColor.r * (floorV + litR * SGValue.float(0.78))
        let g = baseColor.g * (floorV + litG * SGValue.float(0.78))
        let b = baseColor.b * (floorV + litB * SGValue.float(0.78))
        let shaded = SGValue.color3f(r, g, b)

        // Tracking bar: a bright noisy band rolling up in world space.
        let barPos = fract(SGValue.worldPosition.y * SGValue.float(0.8) - SGValue.time * SGValue.float(0.35))
        let inBar = ifGreater(SGValue.float(0.06), barPos, trueResult: 1.0, falseResult: 0.0)
        let barNoise = (fractal3D(amplitude: SGValue.float(1),
                                  octaves: SGValue.int(1),
                                  position: SGValue.worldPosition * SGValue.float(60)
                                            + SGValue.vector3f([1, 0, 0]) * SGValue.time * SGValue.float(40)) as! SGColor).r
        let snow = SGValue.color3f(barNoise, barNoise, barNoise)
        let final = mixColor(fg: snow, bg: shaded, mix: inBar * SGValue.float(0.85))

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 2010s sci-fi hologram: cyan projection built from hard horizontal
    /// slices that scroll slowly, a bright fresnel shell, global projector
    /// flicker, and glitch bands that skip the brightness sideways. The
    /// projection colour is a `HoloColor` shader parameter.
    public static func hologramMaterial() async throws -> ShaderGraphMaterial {
        let holoColor = SGValue.color3fParameter(name: "HoloColor",
                                                 defaultValue: [0.15, 0.85, 1.0])
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let fresnel = clamp(oneMinus(abs(dot(n, v))), min: 0, max: 1)

        // Horizontal slices scrolling upward — the classic projection raster.
        let slice = ifGreater(fract(SGValue.worldPosition.y * SGValue.float(40)
                                    - SGValue.time * SGValue.float(0.8)),
                              SGValue.float(0.35), trueResult: 1.0, falseResult: 0.0)

        // Glitch: occasionally a horizontal band flashes to full brightness.
        // Two beat frequencies multiplied make the skips feel irregular.
        let beat = ifGreater(sin(SGValue.time * SGValue.float(7.3)) * sin(SGValue.time * SGValue.float(1.7)),
                             SGValue.float(0.93), trueResult: 1.0, falseResult: 0.0)
        let glitchBand = ifGreater(fract(SGValue.worldPosition.y * SGValue.float(3.1)
                                         + SGValue.time * SGValue.float(2)),
                                   SGValue.float(0.8), trueResult: 1.0, falseResult: 0.0)
        let glitch = beat * glitchBand

        // Projector hum: fast subtle flicker.
        let hum = SGValue.float(0.85) + sin(SGValue.time * SGValue.float(30)) * SGValue.float(0.15)

        // Fresnel shell bright, faces dim — reads as translucent volume.
        let body = SGValue.float(0.10) + fresnel * SGValue.float(0.55)
        let intensity = clamp((body * slice + fresnel * SGValue.float(0.35)) * hum + glitch,
                              min: 0, max: 1)

        let deep = SGValue.color3f([0.0, 0.02, 0.05])
        let final = mixColor(fg: holoColor, bg: deep, mix: intensity)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1940s film noir: brutal 2-band black-and-white with hard venetian-blind
    /// slat shadows raking across everything at a cinematic angle, slowly
    /// creeping like afternoon light through the blinds, plus dancing silver
    /// halide grain. Somebody's about to get double-crossed.
    public static func filmNoirMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))

        // Brutal 2-band split biased dark — noir is mostly shadow.
        let lit = ifGreater(ndl, SGValue.float(0.45), trueResult: 1.0, falseResult: 0.0)

        // Venetian-blind slats: diagonal world-space stripes that creep slowly,
        // cutting the LIT side into bars of light and darkness.
        let wp = SGValue.worldPosition
        let slatCoord = wp.y * SGValue.float(9) + wp.x * SGValue.float(3.5)
                        + SGValue.time * SGValue.float(0.15)
        let slat = ifGreater(fract(slatCoord), SGValue.float(0.45),
                             trueResult: 1.0, falseResult: 0.0)

        // Silver halide grain, re-rolled every projected frame.
        let frame = floor(SGValue.time * SGValue.float(16))
        let grain = (fractal3D(amplitude: SGValue.float(1),
                               octaves: SGValue.int(1),
                               position: wp * SGValue.float(160)
                                         + SGValue.vector3f([1, 1, 1]) * frame) as! SGColor).r
        let speckle = ifGreater(grain, SGValue.float(0.85), trueResult: 1.0, falseResult: 0.0)

        // Shadow isn't black — it's smoke-gray; light through slats is hot white.
        let v = clamp(SGValue.float(0.06)
                      + lit * slat * SGValue.float(0.90)
                      + lit * SGValue.float(0.06)          // faint fill on the lit side between slats
                      + speckle * SGValue.float(0.10),
                      min: 0, max: 1)
        // Cold silver-nitrate cast: bias faintly blue.
        let final = SGValue.color3f(v * SGValue.float(0.92), v * SGValue.float(0.95), v)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1985 "Take On Me" pencil sketch: warm paper white with graphite
    /// cross-hatching that fills in as the surface turns from the light —
    /// one hatch direction in half-shadow, crossed strokes in deep shadow —
    /// and the whole drawing "boils" at 8 fps like hand-redrawn animation.
    public static func sketchMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41]) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let wp = SGValue.worldPosition

        // Line boil: hatch coordinates jitter every stepped frame so the
        // strokes shimmer like each frame was redrawn by hand.
        let frame = floor(SGValue.time * SGValue.float(8))
        let jitter = (fractal3D(amplitude: SGValue.float(1),
                                octaves: SGValue.int(1),
                                position: SGValue.vector3f([0.37, 0.61, 0.23]) * frame) as! SGColor).r
        let wob = jitter * SGValue.float(0.15)

        // Two diagonal stroke fields in world space.
        let h1 = fract(wp.x * SGValue.float(28) + wp.y * SGValue.float(28) + wob)
        let h2 = fract(wp.x * SGValue.float(28) - wp.y * SGValue.float(28)
                       + wp.z * SGValue.float(14) - wob)
        let stroke1 = ifGreater(SGValue.float(0.35), h1, trueResult: 1.0, falseResult: 0.0)
        let stroke2 = ifGreater(SGValue.float(0.35), h2, trueResult: 1.0, falseResult: 0.0)

        // Shading zones: lit paper, single-hatch half-tone, cross-hatch core.
        let halfShadow = ifGreater(SGValue.float(0.60), ndl, trueResult: 1.0, falseResult: 0.0)
        let deepShadow = ifGreater(SGValue.float(0.30), ndl, trueResult: 1.0, falseResult: 0.0)
        let hatch = clamp(halfShadow * stroke1 + deepShadow * stroke2, min: 0, max: 1)

        // Paper tooth: faint stationary grain so the paper feels real.
        let tooth = (fractal3D(amplitude: SGValue.float(1),
                               octaves: SGValue.int(1),
                               position: wp * SGValue.float(90)) as! SGColor).r

        let paper = SGValue.color3f([0.96, 0.94, 0.88])
        let paperToothed = mixColor(fg: SGValue.color3f([0.88, 0.86, 0.80]), bg: paper,
                                    mix: ifGreater(tooth, SGValue.float(0.8),
                                                   trueResult: 1.0, falseResult: 0.0) * SGValue.float(0.5))
        let graphite = SGValue.color3f([0.13, 0.13, 0.16])
        let final = mixColor(fg: graphite, bg: paperToothed, mix: hatch * SGValue.float(0.85))

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1980s arcade cabinet CRT: the body colour is blasted through vertical
    /// RGB phosphor triad stripes, darkened by horizontal scanlines, and a
    /// bright refresh band rolls down the tube. Lean in close — you can see
    /// the pixels. Body colour is a `BaseColor` shader parameter.
    public static func arcadeMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41],
                                      triadFrequency: Float = 60) async throws -> ShaderGraphMaterial {
        let baseColor = SGValue.color3fParameter(name: "BaseColor",
                                                 defaultValue: [0.10, 0.60, 1.00])
        let n = normalize(SGValue.worldNormal)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let wp = SGValue.worldPosition

        // 3-band cel so the sprite still shades.
        let lit = clamp(floor(ndl * SGValue.float(3) + SGValue.float(0.5)) / SGValue.float(3),
                        min: 0, max: 1)
        let level = SGValue.float(0.35) + lit * SGValue.float(0.65)

        // Vertical phosphor triads: each third of a cell lights only R, G or B.
        // Mix x and z so the stripes read from any viewing angle.
        let cell = fract((wp.x + wp.z * SGValue.float(0.7)) * SGValue.float(triadFrequency)) * SGValue.float(3)
        let isR = ifGreater(SGValue.float(1), cell, trueResult: 1.0, falseResult: 0.0)
        let isG = ifGreater(cell, SGValue.float(1), trueResult: 1.0, falseResult: 0.0)
                  * ifGreater(SGValue.float(2), cell, trueResult: 1.0, falseResult: 0.0)
        let isB = ifGreater(cell, SGValue.float(2), trueResult: 1.0, falseResult: 0.0)
        // Over-drive each phosphor so the triads stay vivid despite masking.
        let boost = SGValue.float(2.2)
        let r = baseColor.r * isR * boost
        let g = baseColor.g * isG * boost
        let b = baseColor.b * isB * boost

        // Horizontal scanline gaps.
        let scan = SGValue.float(0.55)
                   + ifGreater(fract(wp.y * SGValue.float(80)), SGValue.float(0.35),
                               trueResult: 1.0, falseResult: 0.0) * SGValue.float(0.45)

        // Rolling refresh band sweeping down the tube.
        let refresh = ifGreater(SGValue.float(0.08),
                                fract(wp.y * SGValue.float(0.5) + SGValue.time * SGValue.float(0.4)),
                                trueResult: 1.0, falseResult: 0.0)
        let bright = level * scan * (SGValue.float(1) + refresh * SGValue.float(0.6))

        let final = clamp(SGValue.color3f(r, g, b) * bright, min: 0, max: 1)
        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1999 Matrix digital rain: near-black body with columns of phosphor-green
    /// code streaming downward — each column falls at its own speed with a hot
    /// white-green leading glyph — plus a green fresnel rim so the silhouette
    /// reads like it's dissolving into the construct.
    public static func matrixRainMaterial() async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let fresnel = clamp(oneMinus(abs(dot(n, v))), min: 0, max: 1)
        let wp = SGValue.worldPosition

        // Columns keyed on x/z; per-column pseudo-random phase and speed.
        let col = floor((wp.x + wp.z * SGValue.float(0.73)) * SGValue.float(14))
        let colHash = fract(sin(col * SGValue.float(12.9898)) * SGValue.float(43758.5453))

        // Falling brightness: a sawtooth running down each column. The head
        // (just past the reset) is brightest, trailing off behind it.
        let fall = fract(wp.y * SGValue.float(1.4)
                         + SGValue.time * (SGValue.float(0.5) + colHash * SGValue.float(0.9))
                         + colHash * SGValue.float(7))
        let trail = pow(fall, SGValue.float(3.0))                       // long dim tail
        let head = ifGreater(fall, SGValue.float(0.94), trueResult: 1.0, falseResult: 0.0)

        // Glyph cells: a flickering grid mask so the streams read as characters
        // switching, not smooth gradients.
        let frame = floor(SGValue.time * SGValue.float(10))
        let glyphNoise = (fractal3D(amplitude: SGValue.float(1),
                                    octaves: SGValue.int(1),
                                    position: floor(wp * SGValue.float(24))
                                              + SGValue.vector3f([1, 1, 1]) * frame) as! SGColor).r
        let glyph = ifGreater(glyphNoise, SGValue.float(0.35), trueResult: 1.0, falseResult: 0.0)

        let rain = clamp(trail * glyph + fresnel * SGValue.float(0.30), min: 0, max: 1)

        let black = SGValue.color3f([0.0, 0.015, 0.0])
        let green = SGValue.color3f([0.05, 0.95, 0.25])
        let white = SGValue.color3f([0.85, 1.0, 0.90])
        let body = mixColor(fg: green, bg: black, mix: rain)
        let final = mixColor(fg: white, bg: body, mix: head * glyph)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }

    /// 1950s drafting-room blueprint: deep cyanotype blue paper with crisp
    /// white contour lines traced at every cel-band terminator (like elevation
    /// lines on a technical drawing), a faint graph-paper grid, bright white
    /// silhouette linework, and a slow diazo print-exposure shimmer.
    public static func blueprintMaterial(keyLight: SIMD3<Float> = [0.40, 0.82, 0.41],
                                         contourBands: Float = 6) async throws -> ShaderGraphMaterial {
        let n = normalize(SGValue.worldNormal)
        let v = normalize(SGValue.worldViewDirection)
        let light = SGValue.vector3f([keyLight.x, keyLight.y, keyLight.z])
        let ndl = max(dot(n, light), SGValue.float(0))
        let fresnel = clamp(oneMinus(abs(dot(n, v))), min: 0, max: 1)
        let wp = SGValue.worldPosition

        // Contour linework: a thin white line wherever the cel ramp would step.
        let ramp = ndl * SGValue.float(contourBands)
        let edge = abs(fract(ramp) - SGValue.float(0.5))
        let contour = ifGreater(SGValue.float(0.06), edge, trueResult: 1.0, falseResult: 0.0)

        // Graph-paper grid scribed straight onto the surface in world space.
        func gridLine(_ c: SGScalar) -> SGScalar {
            ifGreater(SGValue.float(0.035), abs(fract(c * SGValue.float(8)) - SGValue.float(0.5)),
                      trueResult: 1.0, falseResult: 0.0)
        }
        let grid = clamp(gridLine(wp.x) + gridLine(wp.y) + gridLine(wp.z),
                         min: 0, max: 1)

        // Silhouette ink: hard white edge line from fresnel.
        let edgeInk = ifGreater(fresnel, SGValue.float(0.65), trueResult: 1.0, falseResult: 0.0)

        // Diazo exposure shimmer: the paper breathes slightly, like the print
        // is still developing under the lamp.
        let breathe = SGValue.float(0.92) + sin(SGValue.time * SGValue.float(0.8)) * SGValue.float(0.08)

        // Lit faces are a slightly lighter wash so the form still reads.
        let lit = ifGreater(ndl, SGValue.float(0.5), trueResult: 1.0, falseResult: 0.0)
        let paperDark = SGValue.color3f([0.02, 0.09, 0.30])
        let paperLight = SGValue.color3f([0.05, 0.16, 0.45])
        let paper = mixColor(fg: paperLight, bg: paperDark, mix: lit) * breathe

        let inkAmt = clamp(contour + edgeInk + grid * SGValue.float(0.35), min: 0, max: 1)
        let ink = SGValue.color3f([0.92, 0.97, 1.0])
        let final = mixColor(fg: ink, bg: paper, mix: inkAmt)

        return try await ShaderGraphMaterial(surface: unlitSurface(color: final))
    }
}
