// Histograms over a save's change forms: how many of each type, how often each flag is
// set, and how many each typed decoder read completely. The inspector and the
// real-data test print it.

import Foundation

nonisolated public struct ESSChangeFormTypeCount: Equatable, Sendable {
    public let signature: String
    public var count = 0
    public var compressed = 0
    /// Forms of this type a typed decoder read completely. Zero for types with no decoder.
    public var complete = 0
    /// Forms a typed decoder read in part, by what blocked them.
    public var blocked: [String: Int] = [:]
    /// Forms whose data failed to decode, by error text.
    public var failed: [String: Int] = [:]
    /// Set flag bit -> forms of this type that set it.
    public var flags: [UInt32: Int] = [:]

    /// Whether OpenSky has a typed decoder for this type.
    public var hasDecoder: Bool {
        ESSChangeFormSurvey.decodedSignatures.contains(signature)
    }
}

nonisolated public struct ESSChangeFormSurvey: Equatable, Sendable {
    /// One row per type present, in type table order.
    public let types: [ESSChangeFormTypeCount]

    public static let decodedSignatures: Set = [
        "REFR", "ACHR", "PMIS", "PGRE", "PBEA", "PFLA", "PHZD", "PBAR", "PCON", "PARW",
        "NPC_", "QUST", "INFO"
    ]

    public init(_ forms: [ESSChangeForm]) {
        var rows: [UInt8: ESSChangeFormTypeCount] = [:]
        for form in forms {
            var row = rows[form.typeIndex]
                ?? ESSChangeFormTypeCount(signature: ESSChangeFormType.name(of: form.typeIndex))
            row.count += 1
            row.compressed += form.isCompressed ? 1 : 0
            for bit in 0 ..< 32 where form.flags & (1 << bit) != 0 {
                row.flags[1 << bit, default: 0] += 1
            }
            if row.hasDecoder {
                Self.record(Self.status(of: form), in: &row)
            }
            rows[form.typeIndex] = row
        }
        types = rows.keys.sorted().compactMap { rows[$0] }
    }

    public var total: Int {
        types.reduce(0) { $0 + $1.count }
    }

    public func row(_ signature: String) -> ESSChangeFormTypeCount? {
        types.first { $0.signature == signature }
    }

    private static func record(
        _ outcome: Result<ESSDecodeStatus, ESSError>,
        in row: inout ESSChangeFormTypeCount
    ) {
        switch outcome {
        case .success(.complete): row.complete += 1
        case let .success(.partial(blockedBy)): row.blocked[blockedBy, default: 0] += 1
        case let .failure(error): row.failed[error.description, default: 0] += 1
        }
    }

    /// Runs the type's decoder and keeps only how far it got.
    public static func status(of form: ESSChangeForm) -> Result<ESSDecodeStatus, ESSError> {
        do throws(ESSError) {
            switch form.type?.signature {
            case "NPC_": return try .success(ESSActorBaseChange(form).status)
            case "QUST": return try .success(ESSQuestChange(form).status)
            case "INFO":
                _ = try ESSTopicChange(form)
                return .success(.complete)
            default: return try .success(ESSReferenceChange(form).status)
            }
        } catch {
            return .failure(error)
        }
    }
}
