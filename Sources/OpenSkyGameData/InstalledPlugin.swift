// One active plugin as the System page's Installed Content lists it: its file
// name and what its TES4 header says about it.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct InstalledPlugin: Equatable, Sendable {
    public let name: String
    /// TES4 `CNAM`.
    public let author: String?
    /// TES4 `SNAM`.
    public let summary: String?
    public let masters: [String]

    public init(
        name: String,
        author: String? = nil,
        summary: String? = nil,
        masters: [String] = []
    ) {
        self.name = name
        self.author = author
        self.summary = summary
        self.masters = masters
    }

    /// A header that does not parse leaves only the name.
    public init(name: String, file: ESMFile) {
        let header = try? PluginHeader(tes4: file.tes4)
        self.init(
            name: name, author: header?.author, summary: header?.description,
            masters: header?.masters ?? []
        )
    }
}
