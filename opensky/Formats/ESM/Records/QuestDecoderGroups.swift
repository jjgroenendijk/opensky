// The three grouped runs of a QUST record — stages with their log entries,
// objectives with their targets, and the alias run — split out of
// QuestDecoder.swift so each type body stays inside the strict-lint cap.
//
// Every method here follows the same shape: a marker field flushes the group
// it supersedes, validates its own payload size, and either opens the next
// group or records one tally entry. Nothing throws on content.

import Foundation

nonisolated extension Quest.Contents {
    // MARK: - Stages

    /// INDX, 4 bytes: uint16 stage index, uint8 flags, 1 unused byte.
    mutating func beginStage(_ field: ESMField) throws {
        flushStage()
        guard field.data.count >= 4 else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        var stage = Quest.Stage()
        stage.index = try reader.readUInt16()
        stage.flags = try Quest.Stage.Flags(rawValue: reader.readUInt8())
        openStage = stage
    }

    /// QSDT, one flags byte, opens a log entry inside the current stage.
    mutating func beginLogEntry(_ field: ESMField) throws {
        flushLogEntry()
        guard openStage != nil else {
            note(.orphanField(field.type))
            return
        }
        guard !field.data.isEmpty else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        var entry = Quest.LogEntry()
        entry.flags = try Quest.LogEntry.Flags(rawValue: reader.readUInt8())
        openLogEntry = entry
    }

    mutating func setLogEntryText(_ field: ESMField) throws {
        guard openLogEntry != nil else {
            note(.orphanField(field.type))
            return
        }
        openLogEntry?.text = try LString(field: field, localized: localized)
    }

    mutating func setNextQuest(_ field: ESMField) throws {
        guard openLogEntry != nil else {
            note(.orphanField(field.type))
            return
        }
        guard field.data.count >= 4 else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        openLogEntry?.nextQuest = try FormID(reader.readUInt32())
    }

    mutating func flushLogEntry() {
        guard let entry = openLogEntry else { return }
        openLogEntry = nil
        openStage?.logEntries.append(entry)
    }

    mutating func flushStage() {
        flushLogEntry()
        guard let stage = openStage else { return }
        openStage = nil
        stages.append(stage)
    }

    // MARK: - Objectives

    /// QOBJ, a uint16 index, opens an objective and ends the stage run.
    mutating func beginObjective(_ field: ESMField) throws {
        flushStage()
        flushObjective()
        guard field.data.count >= 2 else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        var objective = Quest.Objective()
        objective.index = try reader.readUInt16()
        openObjective = objective
    }

    /// FNAM at quest level is the objective's ORed-with-previous flag word.
    /// The same four letters inside an alias are that alias's flags, which is
    /// why the alias run intercepts fields before this switch ever sees them.
    mutating func setObjectiveFlags(_ field: ESMField) throws {
        guard openObjective != nil else {
            note(.orphanField(field.type))
            return
        }
        guard field.data.count >= 4 else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        openObjective?.flags = try Quest.Objective.Flags(rawValue: reader.readUInt32())
    }

    /// NNAM is an objective's display text inside the objective run and the
    /// quest's own description once ANAM has ended that run.
    mutating func setDisplayTextOrDescription(_ field: ESMField) throws {
        if openObjective != nil {
            openObjective?.displayText = try LString(field: field, localized: localized)
            return
        }
        guard sawAliasMarker else {
            note(.orphanField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        questDescription = try reader.readZString()
    }

    /// QSTA, 8 bytes: int32 alias or reference, uint8 ignores-locks flag, then
    /// 3 unused bytes. Inside an objective it opens an objective target; after
    /// the alias run it opens a record-level legacy target.
    mutating func beginTarget(_ field: ESMField) throws {
        flushTarget()
        guard openObjective != nil || sawAliasMarker else {
            note(.orphanField(field.type))
            return
        }
        guard field.data.count >= 5 else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        var target = Quest.Target()
        target.rawTarget = try Int32(bitPattern: reader.readUInt32())
        target.compassMarkerIgnoresLocks = try reader.readUInt8() != 0
        openTarget = target
    }

    mutating func flushTarget() {
        guard let target = openTarget else { return }
        openTarget = nil
        if openObjective != nil {
            openObjective?.targets.append(target)
        } else {
            legacyTargets.append(target)
        }
    }

    mutating func flushObjective() {
        flushTarget()
        guard let objective = openObjective else { return }
        openObjective = nil
        objectives.append(objective)
    }

    // MARK: - Aliases

    /// ALST opens a reference alias, ALLS a location alias. Both close any
    /// alias still open, because ALED is the only legal terminator and a
    /// missing one is a mod quirk rather than a reason to lose the record.
    mutating func beginAlias(_ field: ESMField, category: Quest.Alias.Category) throws {
        endAlias(terminated: false)
        flushObjective()
        flushStage()
        guard field.data.count >= 4 else {
            note(.malformedField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        openAlias = try Quest.Alias(id: reader.readUInt32(), category: category)
    }

    /// - Parameter terminated: false when the group ended without its ALED
    ///   terminator, which is recorded but still keeps the alias.
    mutating func endAlias(terminated: Bool) {
        guard let alias = openAlias else {
            if terminated {
                tally.note(.orphanField("ALED"))
            }
            return
        }
        if !terminated {
            tally.note(.unterminatedAlias)
        }
        openAlias = nil
        aliases.append(alias)
    }

    mutating func decodeAliasField(_ field: ESMField) throws {
        guard var alias = openAlias else { return }
        try alias.decode(field: field, tally: &tally)
        openAlias = alias
    }
}
