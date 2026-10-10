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
}
