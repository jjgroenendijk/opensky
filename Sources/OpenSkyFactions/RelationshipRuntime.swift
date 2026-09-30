// Relationship ranks at runtime: the `RELA` records underneath, and what a
// script set on top. Writes go through `WorldStateStore.set`. The script
// override wins, and it is the only layer that can name the player, who has no
// `NPC_` base. Nothing here throws.
// See docs/engine/hostility.md and docs/formats/relationships.md.

import Foundation
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Reads and writes relationship ranks on top of a `WorldStateStore`, with the
/// authored `RELA` records behind them.
@MainActor
public struct RelationshipRuntime: RelationshipAccess {
    /// Load-order RELA and ASTP lookup behind the authored layer.
    public let relationships: RelationshipStore

    private let worldState: WorldStateStore

    public init(store: WorldStateStore, relationships: RelationshipStore) {
        worldState = store
        self.relationships = relationships
    }

    // MARK: - Reading

    /// `key`'s scripted overrides, empty when nothing has ever written one.
    public func state(of key: ReferenceKey) -> ActorRelationshipState {
        worldState.component(ActorRelationshipState.self, for: key) ?? ActorRelationshipState()
    }

    /// The signed Creation Kit rank between two actors, "4: Lover ... -4:
    /// Archnemesis" (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>), or nil
    /// when neither layer names the pair. Nil is not 0 (Acquaintance). `bases` maps
    /// a reference to its `NPC_` identity, nil for the player.
    public func rank(
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        bases: (ReferenceKey) -> ResolvedFormID?
    ) -> Int8? {
        if let override = storedRank(of: observer, toward: target) {
            return override
        }
        guard
            let mine = bases(observer),
            let theirs = bases(target),
            let signed = relationships.rank(between: mine, and: theirs)?.signedRank
        else { return nil }
        return Int8(clamping: signed)
    }

    /// The scripted rank alone, in either direction. Both directions are stored,
    /// so the second read is a fallback for a component written by an older
    /// build rather than a disagreement this one can produce.
    public func storedRank(of observer: ReferenceKey, toward target: ReferenceKey) -> Int8? {
        state(of: observer).rank(toward: target)
            ?? state(of: target).rank(toward: observer)
    }

    // MARK: - Writing

    /// Sets the rank between two actors in both components, as `SetRelationshipRank`
    /// does (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>). `RELA` stores
    /// one record per pair, so either actor can answer alone. An actor set against
    /// itself is refused.
    /// - Returns: true when stored state changed.
    @discardableResult
    public func setRank(
        _ rank: Int8,
        of observer: ReferenceKey,
        toward target: ReferenceKey,
        in cell: CellSceneLocation? = nil,
        targetCell: CellSceneLocation? = nil
    ) -> Bool {
        guard observer != target else { return false }
        let mine = write(
            state(of: observer).setting(rank, toward: target), for: observer, in: cell
        )
        let theirs = write(
            state(of: target).setting(rank, toward: observer), for: target, in: targetCell
        )
        return mine || theirs
    }

    // MARK: - Private

    /// Stores `state`, dropping the whole component once it is empty so an actor
    /// with no overrides stops being dirty for this slot.
    @discardableResult
    private func write(
        _ state: ActorRelationshipState,
        for key: ReferenceKey,
        in cell: CellSceneLocation?
    ) -> Bool {
        guard state != self.state(of: key) else { return false }
        if state.isEmpty {
            worldState.reset(.relationships, for: key)
        } else {
            worldState.set(state, for: key, in: cell)
        }
        return true
    }
}
