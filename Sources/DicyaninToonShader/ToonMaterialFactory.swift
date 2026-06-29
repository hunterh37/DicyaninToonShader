import RealityKit
import ShaderGraphCoder

/// Builds the cel-shading `ShaderGraphMaterial` used by `ToonShadingManager`.
public enum ToonMaterialFactory {

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
