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
}
