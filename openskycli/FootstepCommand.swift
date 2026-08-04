// `footstep [--set <editorID>] [--armature <formid-or-editorid>]`: walk the
// footstep chain (issue #352) read-only and print what each gait's tags
// resolve to. The repeatable probe behind the FSTS/FSTP decode and the
// footstep director's tag routing — the whole chain, from the tag the behavior
// graph raises to the audio file the engine would stream.

import Foundation

enum FootstepCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let setName = try scanner.option("--set")
        let armature = try scanner.option("--armature")
        try scanner.finish()
        let file = try context.loadSkyrimESM()
        let store = FootstepStore(file: file)
        let sounds = SoundRecordStore(file: file)
        print("records: \(store.sets.count) FSTS, \(store.footsteps.count) FSTP, "
            + "\(store.impactDataSets.count) IPDS, \(store.impacts.count) IPCT, "
            + "\(store.armatureSets.count) ARMA with SNDD")
        let set = try resolveSet(store: store, setName: setName, armature: armature, file: file)
        print("set: \(set.editorID ?? "<unnamed>") \(set.formID.description)")
        for gait in FootstepGait.allCases {
            report(gait: gait, set: set, store: store, sounds: sounds)
        }
    }

    private static func resolveSet(
        store: FootstepStore,
        setName: String?,
        armature: String?,
        file: ESMFile
    ) throws -> FootstepSet {
        if let armature {
            guard
                let record = ESMWalk.record(withEditorID: armature, in: file)
                ?? formIDRecord(armature, in: file)
            else {
                throw CLIError.failure("no record named \(armature)")
            }
            guard let id = store.armatureSets[record.formID] else {
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
                    "no FSTS named \(FootstepStore.defaultSetEditorID) in Skyrim.esm"
                )
            }
            return set
        }
        guard let set = store.sets.values.first(where: { $0.editorID == setName }) else {
            throw CLIError.failure("no FSTS with editor ID \(setName)")
        }
        return set
    }

    private static func formIDRecord(_ token: String, in file: ESMFile) -> ESMRecord? {
        var hex = token.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard (1 ... 8).contains(hex.count), let value = UInt32(hex, radix: 16) else {
            return nil
        }
        return ESMWalk.record(withFormID: value, in: file)
    }

    private static func report(
        gait: FootstepGait,
        set: FootstepSet,
        store: FootstepStore,
        sounds: SoundRecordStore
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
                let resolved = store.resolve(tag: tagName, gait: gait, in: set)
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
