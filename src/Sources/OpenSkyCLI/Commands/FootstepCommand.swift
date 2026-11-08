// `footstep [--set <editorID>] [--armature <formid-or-editorid>]
//  [--material <editorID-or-formid>]`: print what each gait's footstep tags
// resolve to, from behavior tag to audio file. `--material` picks the surface;
// without it the table's representative impact is used.

import Foundation
import OpenSkyAudio
import OpenSkyCLIArguments
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

enum FootstepCommand {
    static func run(context: CLIContext, arguments: FootstepArguments) throws {
        let setName = arguments.set
        let armature = arguments.armature
        let materialName = arguments.material
        let loadOrder = try context.loadOrder().plugins
        let store = FootstepStore(loadOrder: loadOrder)
        let sounds = SoundRecordStore(loadOrder: loadOrder)
        let materials = MaterialTypeIndex(loadOrder: loadOrder)
        print("records: \(store.sets.count) FSTS, \(store.footsteps.count) FSTP, "
            + "\(store.impactDataSets.count) IPDS, \(store.impacts.count) IPCT, "
            + "\(store.armatureSets.count) ARMA with SNDD")
        print("materials: \(materials.materials.count) MATT, "
            + "\(materials.hashedMaterialCount) reachable from a collision mesh")
        let set = try resolveSet(
            store: store, setName: setName, armature: armature, loadOrder: loadOrder
        )
        print("set: \(set.editorID ?? "<unnamed>") \(set.formID.description)")
        let material = try resolveMaterial(materialName, in: materials, loadOrder: loadOrder)
        print("material: " + (material.map(materials.describe) ?? "none (representative impact)"))
        for gait in FootstepGait.allCases {
            report(gait: gait, set: set, store: store, sounds: sounds, material: material)
        }
    }

    /// The MATT a `--material` token names, by editor ID, by Creation Kit
    /// material name, or by FormID.
    private static func resolveMaterial(
        _ token: String?,
        in materials: MaterialTypeIndex,
        loadOrder: LoadOrderPlugins
    ) throws -> FormID? {
        guard let token else { return nil }
        let match = materials.materials.values.first {
            $0.editorID == token || $0.materialName == token
        }
        if let match {
            return match.formID
        }
        guard
            let formID = FormID(token: token).flatMap({ loadOrder.record(withFormID: $0) })?.formID,
            let material = materials.material(formID)
        else {
            throw CLIError.failure("no MATT named \(token)")
        }
        return material.formID
    }

    private static func resolveSet(
        store: FootstepStore,
        setName: String?,
        armature: String?,
        loadOrder: LoadOrderPlugins
    ) throws -> FootstepSet {
        if let armature {
            guard let record = loadOrder.record(named: armature) else {
                throw CLIError.failure("no record named \(armature)")
            }
            guard let id = store.armatureSets[record.formID.rawValue] else {
                throw CLIError.failure("\(armature) declares no ARMA.SNDD footstep set")
            }
            guard let set = store.set(id) else {
                throw CLIError.failure("\(armature) points at missing FSTS \(id.description)")
            }
            return set
        }
        guard let setName else {
            guard let set = store.defaultSet else {
                throw CLIError.failure(
                    "no FSTS named \(FootstepStore.defaultSetEditorID) in the load order"
                )
            }
            return set
        }
        guard let set = store.sets.values.first(where: { $0.editorID == setName }) else {
            throw CLIError.failure("no FSTS with editor ID \(setName)")
        }
        return set
    }

    private static func report(
        gait: FootstepGait,
        set: FootstepSet,
        store: FootstepStore,
        sounds: SoundRecordStore,
        material: FormID?
    ) {
        let footsteps = set.footsteps(for: gait)
        print("\(gait) — \(footsteps.count) footstep(s)")
        for id in footsteps {
            guard let footstep = store.footsteps[id.rawValue] else {
                print("  \(id.description): no FSTP record")
                continue
            }
            let tag = footstep.tag ?? "<no ANAM>"
            guard
                let tagName = footstep.tag,
                let resolved = store.resolve(
                    tag: tagName, gait: gait, in: set, material: material
                )
            else {
                print("  \(tag): \(footstep.editorID ?? id.description) — no sound")
                continue
            }
            let path = (try? sounds.resolveAny(resolved.sound))?.filePaths.first
            print("  \(tag): \(footstep.editorID ?? id.description) -> "
                + "\(resolved.impact.editorID ?? resolved.impact.formID.description) -> "
                + (path ?? "\(resolved.sound.description) (no track)"))
        }
    }
}
