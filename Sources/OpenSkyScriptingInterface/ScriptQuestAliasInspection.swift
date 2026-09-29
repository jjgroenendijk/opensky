/// One reference alias of a quest, as the Quests section shows it (issue
/// #183): what the record authored, and what the session filled it with.
nonisolated public struct ScriptQuestAliasRow: Equatable, Sendable {
    /// ALST/ALLS number scripts and conditions address the alias by.
    public let aliasID: UInt32
    /// ALID, the authoring name. Empty when the record carried none.
    public let name: String
    /// `Quest.Alias.FillType.name`, so the readout states *how* an alias is
    /// meant to fill and not only whether it did.
    public let fillType: String
    /// Optional aliases may legitimately stay empty; a non-optional one that
    /// does stops its quest from starting.
    public let isOptional: Bool
    /// `ReferenceKey.description` of the filled reference, or nil when the
    /// alias holds nothing.
    public let reference: String?

    public init(
        aliasID: UInt32,
        name: String,
        fillType: String,
        isOptional: Bool,
        reference: String?
    ) {
        self.aliasID = aliasID
        self.name = name
        self.fillType = fillType
        self.isOptional = isOptional
        self.reference = reference
    }
}

/// One quest's alias table for the Quests section.
nonisolated public struct ScriptQuestAliasInspection: Equatable, Sendable {
    public let editorID: String
    public let formIDText: String
    /// Aliases are filled only while a quest runs, so a stopped quest showing
    /// every row empty is correct rather than broken.
    public let isRunning: Bool
    /// Every alias the record declares, in the file order they fill in.
    public let rows: [ScriptQuestAliasRow]

    public var filledCount: Int {
        rows.count { $0.reference != nil }
    }

    public init(
        editorID: String,
        formIDText: String,
        isRunning: Bool,
        rows: [ScriptQuestAliasRow]
    ) {
        self.editorID = editorID
        self.formIDText = formIDText
        self.isRunning = isRunning
        self.rows = rows
    }
}
