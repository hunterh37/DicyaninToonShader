# DicyaninToonShader

Cel / toon shading with a black inverted-hull outline for RealityKit on Apple Vision Pro. Flag entities with a component, call one manager method, and the whole scene gets a quantized N.L cel ramp plus crisp outlines. Built on ShaderGraphCoder.

Platforms: visionOS 2+ (iOS 18+ builds for tooling and previews).

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/dicyanin/DicyaninToonShader.git", branch: "main")
```

## How it works

visionOS RealityKit does not expose scene lights to a material graph, so the key light direction is baked into the shader as a constant. The cel body is an `unlitSurface` whose `max(N.L, 0)` term is quantized into a fixed number of bands, then blended between a darkened shadow tint and the body colour. The body colour is a `BaseColor` shader parameter, so one compiled graph per band count is re-tinted per entity.

The outline is a duplicated mesh scaled outward and rendered with front-face culling, so only the back faces (the black hull) show behind the real mesh.

## Use

Register components once at launch:

```swift
ToonShadingManager.registerComponents()
```

Style a whole scene by flagging entities, then applying:

```swift
entity.components.set(ToonShadedComponent(baseColor: [0.78, 0.78, 0.80], mode: .full))
await ToonShadingManager.shared.applyToHierarchy(root)
```

Or style one entity directly:

```swift
await ToonShadingManager.shared.style(entity, baseColor: [0.8, 0.2, 0.2], mode: .full)
```

`mode: .outlineOnly` keeps the existing material and adds only the outline. Remove styling with `ToonShadingManager.shared.remove(from: root)`.

## Tuning

`ToonShadedComponent` exposes `baseColor`, `outlineColor`, `outlineScale`, `bands`, and `mode`. `ToonMaterialFactory.celMaterial(bands:keyLight:shadowMix:)` builds the graph directly if you want full control.
