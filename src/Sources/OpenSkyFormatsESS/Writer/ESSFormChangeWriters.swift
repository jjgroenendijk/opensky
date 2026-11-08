// Encoders for the `NPC_`, `QUST`, and `INFO` change forms: the inverses of their
// decoders, writing each present part in the decoder's flag order.
// See docs/formats/ess-change-forms.md.

import Foundation

nonisolated extension ESSActorBaseChange {
    public init(form: ESSRefID) {
        self.form = form
    }

    private typealias Flag = ESSChangeFlag.ActorBase

    public func changeForm() throws(ESSError) -> ESSChangeForm {
        guard status.isComplete else {
            throw .invalidValue(context: "actor base \(form) is only partly decoded")
        }
        var flags: UInt32 = 0
        let data = try ESSWriter.build { writer throws(ESSError) in
            if let formFlags {
                flags |= ESSChangeFlag.formFlags
                writer.uint32(formFlags)
                writer.uint16(0)
            }
            if let baseData {
                guard baseData.count == 24 else {
                    throw .invalidValue(context: "ACBS is \(baseData.count) bytes, not 24")
                }
                flags |= Flag.baseData
                writer.bytes(baseData)
            }
            try writeLists(&writer, flags: &flags)
            if let name {
                flags |= Flag.fullName
                try writer.wstring(name, "full name")
            }
            if let skills {
                guard skills.count == 52 else {
                    throw .invalidValue(context: "DNAM is \(skills.count) bytes, not 52")
                }
                flags |= Flag.skills
                writer.bytes(skills)
            }
            try writeAppearance(&writer, flags: &flags)
        }
        return try ESSChangeForm(form: form, flags: flags, signature: "NPC_", data: data)
    }

    private func writeLists(_ writer: inout ESSWriter, flags: inout UInt32) throws(ESSError) {
        if let factions {
            flags |= Flag.factions
            try writer.count(factions.count, "factions")
            for entry in factions {
                writer.refID(entry.faction)
                writer.int8(entry.rank)
            }
        }
        guard spells != nil || leveledSpells != nil || shouts != nil else { return }
        flags |= Flag.spellList
        let lists = [(spells, "spells"), (leveledSpells, "leveled spells"), (shouts, "shouts")]
        for (list, context) in lists {
            try writer.count(list?.count ?? 0, context)
            list?.forEach { writer.refID($0) }
        }
    }

    private func writeAppearance(
        _ writer: inout ESSWriter, flags: inout UInt32
    ) throws(ESSError) {
        if let npcClass {
            flags |= Flag.npcClass
            writer.refID(npcClass)
        }
        if let race {
            flags |= Flag.race
            writer.refID(race)
            // The previous race; the reader drops it.
            writer.refID(race)
        }
        if let face {
            flags |= Flag.face
            try face.write(into: &writer)
        }
        if let isFemale {
            flags |= Flag.gender
            writer.uint8(isFemale ? 1 : 0)
        }
    }
}

nonisolated extension ESSFace {
    func write(into writer: inout ESSWriter) throws(ESSError) {
        writer.uint8(1)
        writer.refID(hairColor)
        writer.bytes(Data([skinTone.x, skinTone.y, skinTone.z, skinTone.w]))
        writer.refID(skin)
        try writer.count(headParts.count, "head parts")
        headParts.forEach { writer.refID($0) }
        guard !morphs.isEmpty || !presets.isEmpty else {
            writer.uint8(0)
            return
        }
        writer.uint8(1)
        try writer.count32(morphs.count, "face morphs")
        morphs.forEach { writer.float32($0) }
        try writer.count32(presets.count, "face presets")
        presets.forEach { writer.int32($0) }
    }
}

nonisolated extension ESSQuestChange {
    public init(form: ESSRefID) {
        self.form = form
    }

    private typealias Flag = ESSChangeFlag.Quest

    public func changeForm() throws(ESSError) -> ESSChangeForm {
        guard status.isComplete else {
            throw .invalidValue(context: "quest \(form) is only partly decoded")
        }
        var flags: UInt32 = 0
        let data = try ESSWriter.build { writer throws(ESSError) in
            if let formFlags {
                flags |= ESSChangeFlag.formFlags
                writer.uint32(formFlags)
                writer.uint16(0)
            }
            if let questFlags {
                flags |= Flag.flags
                writer.uint16(questFlags)
            }
            if let scriptDelay {
                flags |= Flag.scriptDelay
                writer.float32(scriptDelay)
            }
            if let stages {
                flags |= Flag.stages
                try writer.count(stages.count, "quest stages")
                for stage in stages {
                    writer.int16(stage.index)
                    writer.uint8(stage.isDone ? 1 : 0)
                }
            }
            if let objectives {
                flags |= Flag.objectives
                try writer.count(objectives.count, "quest objectives")
                for objective in objectives {
                    writer.uint32(objective.first)
                    writer.uint32(objective.second)
                }
            }
            if let alreadyRun {
                flags |= Flag.alreadyRun
                writer.uint8(alreadyRun ? 1 : 0)
            }
        }
        return try ESSChangeForm(form: form, flags: flags, signature: "QUST", data: data)
    }
}

nonisolated extension ESSTopicChange {
    public init(form: ESSRefID, saidOnce: Bool) {
        self.form = form
        self.saidOnce = saidOnce
    }

    /// The said-once flag carries no data.
    public func changeForm() throws(ESSError) -> ESSChangeForm {
        try ESSChangeForm(
            form: form, flags: saidOnce ? ESSChangeFlag.Topic.saidOnce : 0, signature: "INFO",
            data: Data()
        )
    }
}
