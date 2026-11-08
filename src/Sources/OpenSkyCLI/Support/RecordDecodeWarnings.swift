// CLI output for records a command could not decode. Warnings go to stderr, so
// the stdout lines that `tools/probe.sh` greps stay stable.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// Decodes `record`, or prints a `[WARNING]` naming it and returns nil.
func decodeOrWarn<Value>(_ record: ESMRecord, using decode: (ESMRecord) throws -> Value) -> Value? {
    do {
        return try decode(record)
    } catch {
        printError("[WARNING] skipped \(record.type) \(FormID(record.formID)): \(error)")
        return nil
    }
}

/// The group's children, or a printed `[WARNING]` and nil.
func childrenOrWarn(_ group: ESMGroup) -> [ESMGroup.Child]? {
    do {
        return try group.children()
    } catch {
        printError("[WARNING] skipped malformed \(group.recordType ?? "GRUP") group: \(error)")
        return nil
    }
}

extension SkippedRecords {
    func printWarnings() {
        for line in lines {
            printError("[WARNING] \(line)")
        }
    }
}
