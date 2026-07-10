import SwiftUI
import RealityKit
import DicyaninToonShader

/// Every toon look the demo can switch between, mapped to `ToonMode`.
enum DemoStyle: String, CaseIterable, Identifiable {
    case celFull      = "Cel + Outline"
    case outlineOnly  = "Outline Only"
    case wireframe    = "Wireframe"
    case envirobear   = "Enviro-Bear"
    case rubberHose   = "1930s Rubber Hose"
    case filmNoir     = "1940s Film Noir"
    case blueprint    = "1950s Blueprint"
    case popArt       = "1950s Pop Art"
    case psychedelic  = "1960s Psychedelic"
    case blacklight   = "1970s Blacklight"
    case synthwave    = "1980s Synthwave"
    case arcade       = "1980s Arcade CRT"
    case sketch       = "1985 Pencil Sketch"
    case thermal      = "1987 Thermal"
    case gameboy      = "1990s Game Boy"
    case vhs          = "1990s VHS"
    case matrixRain   = "1999 Matrix Rain"
    case y2kChrome    = "2000s Y2K Chrome"
    case hologram     = "2010s Hologram"

    var id: String { rawValue }

    var mode: ToonMode {
        switch self {
        case .celFull:     return .full
        case .outlineOnly: return .outlineOnly
        case .wireframe:   return .wireframe
        case .envirobear:  return .envirobear
        case .rubberHose:  return .rubberHose
        case .filmNoir:    return .filmNoir
        case .blueprint:   return .blueprint
        case .popArt:      return .popArt
        case .psychedelic: return .psychedelic
        case .blacklight:  return .blacklight
        case .synthwave:   return .synthwave
        case .arcade:      return .arcade
        case .sketch:      return .sketch
        case .thermal:     return .thermal
        case .gameboy:     return .gameboy
        case .vhs:         return .vhs
        case .matrixRain:  return .matrixRain
        case .y2kChrome:   return .y2kChrome
        case .hologram:    return .hologram
        }
    }
}

struct ContentView: View {
    @State private var style: DemoStyle = .celFull
    @State private var outlineScale: Double = 1.045
    @State private var bands: Double = 3
    @State private var spinning = true

    // Persistent holder so we can swap the styled scene in place on change.
    @State private var holder = Entity()

    var body: some View {
        RealityView { content in
            content.add(holder)
        }
        .task(id: rebuildKey) { await rebuild() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            controls
        }
    }

    /// Anything that changes the built scene bumps this so `.task(id:)` rebuilds.
    private var rebuildKey: String {
        "\(style.id)|\(outlineScale)|\(bands)"
    }

    @MainActor
    private func rebuild() async {
        holder.children.forEach { $0.removeFromParent() }

        let scene = DemoScene.build(mode: style.mode,
                                    outlineScale: Float(outlineScale),
                                    bands: Float(bands))
        // Sit the turntable near the bottom of the volume and lift it a touch.
        scene.position = [0, -0.28, 0]
        holder.addChild(scene)

        await ToonShadingManager.shared.applyToHierarchy(scene)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Style", selection: $style) {
                ForEach(DemoStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 320)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Outline \(outlineScale, specifier: "%.3f")").font(.caption)
                    Slider(value: $outlineScale, in: 1.0...1.12)
                        .frame(width: 200)
                }
                VStack(alignment: .leading) {
                    Text("Cel bands \(Int(bands))").font(.caption)
                    Slider(value: $bands, in: 1...6, step: 1)
                        .frame(width: 160)
                        .disabled(style != .celFull)
                }
                Toggle("Spin", isOn: $spinning)
                    .toggleStyle(.button)
                    .onChange(of: spinning) { _, on in
                        setSpin(on)
                    }
            }
            .font(.caption)
        }
        .padding(20)
        .glassBackgroundEffect()
    }

    private func setSpin(_ on: Bool) {
        guard let table = holder.findEntity(named: "Turntable") else { return }
        table.components.set(TurntableComponent(speed: on ? 0.3 : 0))
    }
}
