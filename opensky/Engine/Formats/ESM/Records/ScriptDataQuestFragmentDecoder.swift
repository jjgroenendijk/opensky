// The QUST tail of a VMAD field, decoded on top of the primary-script decoder
// in ScriptDataDecoder.swift. It lives in its own file so that decoder's type
// body stays inside the strict-lint cap; the two halves are one type because
// the alias sections reuse the primary script, property and object readers
// unchanged, including the version and object-format handling.
//
// Layout and references: ScriptDataQuestFragments.swift.

import Foundation

nonisolated extension ScriptDataDecoder {
    /// Decodes the QUST tail, reporting whether the whole remainder was
    /// consumed. A malformed tail is not fatal: the caller falls back to the
    /// recorded skip, so the primary scripts of a quest with a broken fragment
    /// table still reach the runtime (AGENTS.md mod-quirk rule).
    mutating func decodeQuestFragmentTail() -> Bool {
        let start = reader.offset
        do {
            let section = try decodeQuestFragments()
            guard reader.bytesRemaining == 0 else {
                reader.seek(to: start)
                return false
            }
            questFragments = section
            return true
        } catch {
            reader.seek(to: start)
            return false
        }
    }

    mutating func decodeQuestFragments() throws -> QuestFragmentSection {
        let bindVersion = try Int8(bitPattern: reader.readUInt8())
        // 13 bytes is the shortest a fragment can be: 2 + 2 + 4 + 1 header
        // bytes plus two empty length-prefixed strings.
        let declaredCount = try checkedCount(
            UInt32(reader.readUInt16()),
            minimumSize: 13,
            context: "quest fragments"
        )
        let fileName = try readString()
        var fragments: [QuestFragment] = []
        fragments.reserveCapacity(declaredCount)
        for _ in 0 ..< declaredCount {
            try fragments.append(decodeQuestFragment())
        }
        return try QuestFragmentSection(
            extraBindDataVersion: bindVersion,
            fileName: fileName,
            declaredFragmentCount: declaredCount,
            fragments: fragments,
            aliasScripts: decodeQuestAliasScripts()
        )
    }

    mutating func decodeQuestFragment() throws -> QuestFragment {
        let stageIndex = try reader.readUInt16()
        reader.skip(2) // always 0
        let logEntryIndex = try Int32(bitPattern: reader.readUInt32())
        reader.skip(1) // always 1
        return try QuestFragment(
            stageIndex: stageIndex,
            logEntryIndex: logEntryIndex,
            scriptName: readString(),
            functionName: readString()
        )
    }

    /// The alias-script array closes the section. It is absent rather than
    /// zero-length in a truncated tail, so an exhausted reader is treated as
    /// "no alias scripts" instead of a decode failure.
    mutating func decodeQuestAliasScripts() throws -> [QuestAliasScripts] {
        guard reader.bytesRemaining >= 2 else { return [] }
        // 14 bytes minimum: an 8-byte object, version, object format, count.
        let count = try checkedCount(
            UInt32(reader.readUInt16()),
            minimumSize: 14,
            context: "quest alias scripts"
        )
        var aliases: [QuestAliasScripts] = []
        aliases.reserveCapacity(count)
        for _ in 0 ..< count {
            try aliases.append(decodeQuestAliasScript())
        }
        return aliases
    }

    /// Each alias restates the version and object format its own scripts use.
    /// UESP records that both always match the primary header, but they are
    /// honoured rather than assumed: the script entries after them are read
    /// with whatever this alias declares, then the primary values are restored.
    mutating func decodeQuestAliasScript() throws -> QuestAliasScripts {
        let object = try decodeObject(notingAlias: false)
        let outerVersion = version
        let outerFormat = objectFormat
        defer {
            version = outerVersion
            objectFormat = outerFormat
        }
        let aliasVersion = try Int16(bitPattern: reader.readUInt16())
        guard (2 ... 5).contains(aliasVersion) else {
            throw ScriptDataError.unsupportedVersion(aliasVersion)
        }
        version = aliasVersion
        let rawFormat = try Int16(bitPattern: reader.readUInt16())
        guard let format = ScriptObjectFormat(rawValue: rawFormat) else {
            throw ScriptDataError.unsupportedObjectFormat(rawFormat)
        }
        objectFormat = format

        let scriptCount = try checkedCount(
            UInt32(reader.readUInt16()),
            minimumSize: version >= 4 ? 5 : 4,
            context: "alias scripts"
        )
        var scripts: [AttachedScript] = []
        scripts.reserveCapacity(scriptCount)
        for _ in 0 ..< scriptCount {
            try scripts.append(decodeScript())
        }
        return QuestAliasScripts(
            object: object,
            version: aliasVersion,
            objectFormat: format,
            scripts: scripts
        )
    }
}
