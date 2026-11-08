public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyProgressionInterface

/// What the world adapters use of `CasterRuntime`.
public protocol CasterRuntimePort: SpellCasting {
    associatedtype SpellCastState: SpellCastStatePort
    associatedtype SpellbookRuntime: SpellbookRuntimePort
    @discardableResult func begin(
        _ hand: SpellHand,
        on caster: ActorValueHolder
    ) -> SpellCastOutcome
    func cancel(_ hand: SpellHand, on caster: ActorValueHolder)
    func isCasting(_ caster: ReferenceKey) -> Bool
    var perks: (any PerkAccess)? { get set }
    func phase(of hand: SpellHand, on caster: ReferenceKey) -> SpellCastPhase
    @discardableResult func release(
        _ hand: SpellHand,
        on caster: ActorValueHolder
    ) -> SpellCastOutcome
    var spellbook: SpellbookRuntime { get }
    func state(of hand: SpellHand, on caster: ReferenceKey) -> SpellCastState
}

/// The default arguments a protocol requirement cannot carry.
extension CasterRuntimePort {
    @discardableResult public func state(of hand: SpellHand) -> SpellCastState {
        state(of: hand, on: .player)
    }

    @discardableResult public func phase(of hand: SpellHand) -> SpellCastPhase {
        phase(of: hand, on: .player)
    }
}
