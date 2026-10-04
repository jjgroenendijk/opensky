// The race menu rules: which rows show, how each one steps, and the limited
// mode scripts open. See docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM

/// One playable race the menu offers.
nonisolated public struct RaceChoice: Equatable, Sendable {
    public let formID: FormID
    public let name: String

    public init(formID: FormID, name: String) {
        self.formID = formID
        self.name = name
    }
}

nonisolated public enum RaceMenuRow: Equatable, Sendable {
    case race, sex, weight, name
    /// A NAM9 slider by index.
    case slider(Int)
    /// A NAMA group by index: 0 nose, 2 eyes, 3 mouth.
    case part(Int)
}

nonisolated public enum RaceMenuAction: Equatable, Sendable {
    case done
    /// Accept on the name row: the next keys type the name.
    case editName
}

nonisolated public struct RaceMenuModel: Equatable, Sendable {
    /// NAM9 sliders the menu shows; the last one, the vampire morph, stays hidden.
    public static let sliderLabels = [
        "Nose Length", "Nose Height", "Jaw Height", "Jaw Width", "Jaw Forward",
        "Cheekbone Height", "Cheekbone Width", "Eye Height", "Eye Depth In", "Brow Height",
        "Brow Width", "Brow Forward", "Mouth Height", "Mouth Forward", "Chin Width",
        "Chin Height", "Chin Forward", "Eye Depth"
    ]
    public static let morphCount = 19
    /// Measured: the female chargen TRI has 30 nose, 28 eye, and 30 lip targets.
    public static let partRanges: [Int: ClosedRange<Int32>] = [
        0: 0 ... 30,
        2: 0 ... 28,
        3: 0 ... 30
    ]
    public static let partLabels: [Int: String] = [0: "Nose Type", 2: "Eye Shape", 3: "Mouth Type"]
    public static let sliderStep: Float = 0.1

    public private(set) var identity: PlayerIdentityState
    public let races: [RaceChoice]
    /// `ShowLimitedRaceMenu`: no name or sex change, and the race locks once
    /// the player leaves its row.
    public let isLimited: Bool
    public private(set) var raceLocked = false
    public private(set) var selectedIndex = 0

    public init(identity: PlayerIdentityState, races: [RaceChoice], limited: Bool) {
        var identity = identity
        if identity.face.morphs.count < Self.morphCount {
            identity.face.morphs += Array(
                repeating: 0, count: Self.morphCount - identity.face.morphs.count
            )
        }
        if identity.face.parts.count < 4 {
            identity.face.parts += Array(repeating: 0, count: 4 - identity.face.parts.count)
        }
        self.identity = identity
        self.races = races
        isLimited = limited
    }

    public var rows: [RaceMenuRow] {
        var rows: [RaceMenuRow] = []
        if !raceLocked {
            rows.append(.race)
        }
        if !isLimited {
            rows.append(.sex)
        }
        rows.append(.weight)
        rows += Self.sliderLabels.indices.map(RaceMenuRow.slider)
        rows += [.part(0), .part(2), .part(3)]
        if !isLimited {
            rows.append(.name)
        }
        return rows
    }

    public var selectedRow: RaceMenuRow {
        rows[min(selectedIndex, rows.count - 1)]
    }

    public mutating func handle(_ event: MenuInputEvent) -> RaceMenuAction? {
        switch event {
        case .move(.up): moveSelection(by: -1)
        case .move(.down): moveSelection(by: 1)
        case .move(.left): step(selectedRow, by: -1)
        case .move(.right): step(selectedRow, by: 1)
        case .button(.accept): return selectedRow == .name ? .editName : .done
        case .button(.cancel): return .done
        case .pointer, .release: break
        }
        return nil
    }

    public mutating func moveSelection(by delta: Int) {
        let leaving = selectedRow
        let count = rows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        if isLimited, leaving == .race, selectedRow != .race {
            raceLocked = true
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    public mutating func step(_ row: RaceMenuRow, by delta: Int) {
        switch row {
        case .race:
            guard !races.isEmpty else { return }
            let current = races.firstIndex { $0.formID == identity.race } ?? 0
            identity.race = races[((current + delta) % races.count + races.count) % races.count]
                .formID
        case .sex:
            identity.isFemale.toggle()
        case .weight:
            identity.face.weight = min(max(identity.face.weight + Float(delta) * 5, 0), 100)
        case let .slider(index):
            let value = identity.face.morphs[index] + Float(delta) * Self.sliderStep
            identity.face.morphs[index] = (min(max(value, -1), 1) * 10).rounded() / 10
        case let .part(index):
            guard let range = Self.partRanges[index] else { return }
            identity.face.parts[index] = min(
                max(identity.face.parts[index] + Int32(delta), range.lowerBound), range.upperBound
            )
        case .name:
            return
        }
    }

    public mutating func setName(_ name: String) {
        guard !isLimited else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        identity.name = String(trimmed.prefix(PlayerIdentityState.nameLimit))
    }

    public func label(_ row: RaceMenuRow) -> String {
        switch row {
        case .race: "Race"
        case .sex: "Sex"
        case .weight: "Weight"
        case .name: "Name"
        case let .slider(index): Self.sliderLabels[index]
        case let .part(index): Self.partLabels[index] ?? "Part"
        }
    }

    public func value(_ row: RaceMenuRow) -> String {
        switch row {
        case .race: races.first { $0.formID == identity.race }?.name ?? "\(identity.race)"
        case .sex: identity.isFemale ? "Female" : "Male"
        case .weight: "\(Int(identity.face.weight))"
        case .name: identity.name
        case let .slider(index): String(format: "%.1f", identity.face.morphs[index])
        case let .part(index): "\(identity.face.parts[index])"
        }
    }
}
