// Relationship ranks at runtime (issue #508, roadmap item 21.4): the authored
// `RELA` record underneath, and whatever a script has said since on top.
//
// A thin layer beside `WorldStateStore` in the shape of `FactionRuntime`. Every
// mutation writes through `WorldStateStore.set`, so a scripted relationship
// lands in the journal, in the dirty counts and in the save exactly as a joined
// faction does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window.
//
// ## The two layers, and which wins
//
// `RelationshipStore` answers from the `RELA` records, keyed by the two `NPC_`
// bases. `ActorRelationshipState` answers from what a script set, keyed by the
// two placed references. The override wins, because that is what "set" means and
// because the record is the starting state a script is deliberately changing.
//
// The override is also the only layer that can speak about the player, who has
// no `NPC_` base in this engine — see the header of
// `ActorRelationshipComponent.swift`. So a vanilla script's
// `SetRelationshipRank(Game.GetPlayer(), 3)` is readable afterwards while
// `GetRelationshipRank` against an untouched player pair reports a gap rather
// than inventing Acquaintance.
//
// Failure model: nothing here throws. Every operation is a component read or
// write, and an actor nothing has written about simply has no override.
//
// Documented in docs/engine/hostility.md and docs/formats/relationships.md.

import Foundation
import OpenSkyFormats

/// Reads and writes relationship ranks on top of a `WorldStateStore`, with the
/// authored `RELA` records behind them.
@MainActor
struct RelationshipRuntime {
    /// Load-order RELA and ASTP lookup behind the authored layer.
    let relationships: RelationshipStore

    private let worldState: WorldStateStore

    init(store: WorldStateStore, relationships: RelationshipStore) {
        worldState = store
        self.relationships = relationships
    }

    var store: WorldStateStore {
        worldState
    }

    // MARK: - Reading

    /// `key`'s scripted overrides, empty when nothing has ever written one.
    func state(of key: ReferenceKey) -> ActorRelationshipState {
        worldState.component(ActorRelationshipState.self, for: key) ?? ActorRelationshipState()
    }

    /// The signed Creation Kit rank between two actors — "4: Lover ... -4:
    /// Archnemesis" (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>) —
    /// or nil when neither layer names the pair.
    ///
    /// Nil is not 0: 0 is Acquaintance, a rank a record and a script both author
    /// deliberately, and a caller has to be able to tell it from "nothing says".
    ///
    /// `bases` maps a reference to the `NPC_` identity a `RELA` record would
    /// name, and answers nil for an actor that has none — the player, and any
    /// actor no plugin describes.
    func rank(
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
    func storedRank(of observer: ReferenceKey, toward target: ReferenceKey) -> Int8? {
        state(of: observer).rank(toward: target)
            ?? state(of: target).rank(toward: observer)
    }

    // MARK: - Writing

    /// Sets the rank between two actors, in both components.
    ///
    /// "Sets the relationship rank between this actor and another."
    /// (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>) A relationship is
    /// one fact about a pair rather than two opinions — `RELA` stores a single
    /// record for it — so both sides are written and either actor can answer
    /// alone.
    ///
    /// An actor set against itself is refused: no `RELA` record names a base
    /// twice, and storing one would make `rank(of:toward:)` answer a question
    /// the records cannot pose.
    ///
    /// - Returns: true when stored state changed.
    @discardableResult
    func setRank(
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
