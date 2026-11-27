// What a placed primitive's `XTRI` collision layer makes it (docs/engine/trigger-volumes.md).

import Foundation
import OpenSkyFormatsCore

nonisolated public struct CollisionLayerRoles: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        /// Fires enter and leave events.
        case trigger
        /// Blocks actors like static collision.
        case solid
        /// Neither, such as a navmesh cut box.
        case neither
    }

    /// The `COLL` index of `L_CHARCONTROLLER`, the layer an actor moves on.
    static let characterControllerIndex: UInt32 = 30

    private let triggers: Set<UInt32>
    private let solids: Set<UInt32>

    /// No layers loaded: every primitive stays a trigger.
    public static let empty = Self(triggers: [], solids: [])

    init(triggers: Set<UInt32>, solids: Set<UInt32>) {
        self.triggers = triggers
        self.solids = solids
    }

    /// A layer with `COLL` flag 0x01 is a trigger; one the character layer's `CNAM`
    /// names is solid.
    public init(layers: [CollisionLayer]) {
        let character = layers.first { $0.index == Self.characterControllerIndex }
        let blocking = Set(character?.collidesWith ?? [])
        self.init(
            triggers: Set(layers.filter { $0.flags.contains(.triggerVolume) }.compactMap(\.index)),
            solids: Set(layers.filter { blocking.contains($0.formID) }.compactMap(\.index))
        )
    }

    public init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        self.init(layers: loadOrder.decodeRecords(of: "COLL", skipped: &skipped) {
            try CollisionLayer(record: $0, localized: $1)
        })
    }

    /// No `XTRI`, or no layers loaded, keeps the primitive a trigger.
    public func role(ofLayer index: UInt32?) -> Role {
        guard let index, self != .empty else { return .trigger }
        if triggers.contains(index) {
            return .trigger
        }
        return solids.contains(index) ? .solid : .neither
    }
}
