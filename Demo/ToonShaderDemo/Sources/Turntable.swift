import RealityKit
import simd

/// Spins a flagged entity slowly around its Y axis so every side of the props
/// rotates through the baked key-light direction. A hand-rolled system (rather
/// than an OrbitAnimation) keeps the behaviour trivial and dependency-free.
public struct TurntableComponent: Component {
    /// Radians per second.
    public var speed: Float
    public init(speed: Float = 0.35) { self.speed = speed }
}

public struct TurntableSystem: System {
    static let query = EntityQuery(where: .has(TurntableComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let c = entity.components[TurntableComponent.self] else { continue }
            entity.orientation *= simd_quatf(angle: c.speed * dt, axis: [0, 1, 0])
        }
    }
}
