import Foundation
import OpenSkyFormatsESM

nonisolated extension ActorTemplateResolver {
    /// `VMAD` scripts after template inheritance, through `useScript` (UESP `NPC_` template flags).
    public func resolveScripts(base: FormID) throws -> ActorSourcedField<[AttachedScript]> {
        let (npcs, _) = try resolveChain(base: base)
        return resolveField(in: npcs, flag: .useScript) {
            ActorSourcedField(value: $0.scriptData.scripts, source: $0.formID)
        }
    }

    /// `INAM`, the death item, through `useTraits`: the Creation Kit shows it on the
    /// Traits tab (docs/engine/actor-resolution.md).
    public func resolveDeathItem(base: FormID) throws -> ActorSourcedField<FormID?> {
        let (npcs, _) = try resolveChain(base: base)
        return resolveField(in: npcs, flag: .useTraits) {
            ActorSourcedField(value: $0.details.deathItem, source: $0.formID)
        }
    }

    /// The `CNTO` items an actor carries, through `useInventory`, the flag that also
    /// carries the default outfit (UESP `NPC_` template flags).
    public func resolveCarriedItems(base: FormID) throws -> ActorSourcedField<[Container.Entry]> {
        let (npcs, _) = try resolveChain(base: base)
        return resolveField(in: npcs, flag: .useInventory) {
            ActorSourcedField(value: $0.details.inventory, source: $0.formID)
        }
    }
}
