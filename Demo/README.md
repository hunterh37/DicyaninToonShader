# ToonShaderDemo

A tiny volumetric visionOS app that applies `DicyaninToonShader` live to a
turntable of cubes and low-poly props (tree, mushroom, crate, barrel, crystal,
gem, lantern, flower, rock, pine — recreated from the VisionSocial build
catalog's flat-matte vocabulary).

## Run it

```sh
cd Demo/ToonShaderDemo
xcodegen generate          # produces ToonShaderDemo.xcodeproj
open ToonShaderDemo.xcodeproj
```

Pick an **Apple Vision Pro** simulator and hit Run. The project references the
`DicyaninToonShader` package two directories up (`path: ../..`), which in turn
resolves `ShaderGraphCoder` from its sibling folder.

## What you can poke

The ornament under the volume lets you:

- Switch between all nine looks — Cel + Outline, Outline Only, Wireframe,
  Enviro-Bear, Pop Art, Psychedelic, Synthwave, Game Boy, Y2K Chrome.
- Drag the **Outline** slider to fatten/thin the inverted-hull silhouette.
- Drag **Cel bands** (1–6) to change the ramp step count (cel mode only).
- Toggle the **Spin** turntable.

Each prop is flagged with its own `ToonShadedComponent` carrying a distinct
tint, so `ToonShadingManager.applyToHierarchy` cel-shades every prop in its own
colour. Decade styles ignore the tint and pick their own palettes.
