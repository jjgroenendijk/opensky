// Resolving a dialogue response's text through the plugin's string tables, which
// the engine loads. The record shape lives with the parsers in OpenSkyFormatsESM.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension TopicInfo.Response {
    /// Dialogue response text is stored in the plugin's ILSTRINGS table.
    public func resolvedText(using strings: LocalizedStrings) -> String? {
        strings.resolve(text, kind: .ilstrings)
    }
}
