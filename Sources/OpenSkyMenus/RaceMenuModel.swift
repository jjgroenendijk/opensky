// The race menu rules: which rows show, how the keys move between them, and the
// limited mode scripts open. Each row's values are in RaceMenuModel+Values.swift.
// See docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM

/// One playable race the menu offers.
nonisolated public struct RaceChoice: Equatable, Sendable {
    public let formID: FormID
    public let name: String
    /// `RACE` `DESC`; the movie prints its own placeholder when this is empty.
    public let description: String

    public init(formID: FormID, name: String, description: String = "") {
        self.formID = formID
        self.name = name
        self.description = description
    }
}

nonisolated public enum RaceMenuAction: Equatable, Sendable {
    case done
    /// Accept on the name row: the next keys type the name.
    case editName
}

nonisolated public struct RaceMenuModel: Equatable, Sendable {
    /// English names of the `NAM9` sliders, nose long or short first, for the readout.
    public static let sliderLabels = [
        "Nose Length", "Nose Height", "Jaw Height", "Jaw Width", "Jaw Forward",
        "Cheekbone Height", "Cheekbone Width", "Eye Height", "Eye Width", "Brow Height",
        "Brow Width", "Brow Forward", "Mouth Height", "Mouth Forward", "Chin Width",
        "Chin Length", "Chin Forward", "Eye Depth"
    ]
    public static let morphCount = 19
    /// Measured: the female chargen TRI has 30 nose, 28 eye, and 30 lip targets.
    public static let partRanges: [Int: ClosedRange<Int32>] = [
        0: 0 ... 30,
        2: 0 ... 28,
        3: 0 ... 30
    ]
    public static let sliderStep: Float = 0.1

    public internal(set) var identity: PlayerIdentityState
    public let races: [RaceChoice]
    public var labels = RaceMenuLabels()
    /// What the current race and sex offer. The coordinator replaces it after a change.
    public internal(set) var options: RaceMenuOptions
    /// `ShowLimitedRaceMenu`: no name or sex change, and the race locks once
    /// the player leaves its row.
    public let isLimited: Bool
    public private(set) var raceLocked = false
    public private(set) var selectedIndex = 0
    /// The preset face last applied; presets are not stored on the face.
    public internal(set) var presetIndex = 0

    public init(
        identity: PlayerIdentityState, races: [RaceChoice], limited: Bool,
        options: RaceMenuOptions = .empty
    ) {
        var identity = identity
        identity.face = Self.padded(identity.face)
        self.identity = identity
        self.races = races
        self.options = options
        isLimited = limited
    }

    /// The rows in the vanilla order, without those the race offers nothing for.
    public var rows: [RaceMenuRow] {
        Self.layout.map(\.row).filter(isShown) + (isLimited ? [] : [.name])
    }

    private func isShown(_ row: RaceMenuRow) -> Bool {
        switch row {
        case .race: !raceLocked
        case .sex, .name: !isLimited
        case .weight, .slider, .part: true
        case .headPreset: !options.presets.isEmpty
        case let .headPart(type): !(options.headParts[type] ?? []).isEmpty
        case .hairColor: !options.hairColors.isEmpty
        case .complexion: !options.complexions.isEmpty
        case let .tintColor(type), let .tintMask(type): !options.masks(ofType: type).isEmpty
        }
    }

    public var selectedRow: RaceMenuRow {
        let rows = rows
        return rows[min(selectedIndex, rows.count - 1)]
    }

    public mutating func handle(_ event: MenuInputEvent) -> RaceMenuAction? {
        switch event {
        case .move(.up): moveSelection(by: -1)
        case .move(.down): moveSelection(by: 1)
        case .move(.left): step(selectedRow, by: -1)
        case .move(.right): step(selectedRow, by: 1)
        case .button(.accept): return selectedRow == .name ? .editName : .done
        case .button(.cancel), .button(.xButton): return .done
        case .pointer, .release, .button(.yButton): break
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

    /// Picks a race by its place in `races`. A limited menu keeps the race once left.
    public mutating func selectRace(at index: Int) {
        guard races.indices.contains(index), !raceLocked else { return }
        identity.race = races[index].formID
    }

    public mutating func setName(_ name: String) {
        guard !isLimited else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        identity.name = String(trimmed.prefix(PlayerIdentityState.nameLimit))
    }

    /// New options after a race or sex change. The face takes the race's first
    /// preset, so no head part of the old race stays on it.
    public mutating func setOptions(_ options: RaceMenuOptions) {
        self.options = options
        presetIndex = 0
        if let preset = options.presets.first {
            applyPreset(preset)
        } else {
            identity.face.headParts = []
            identity.face.tints = []
            identity.face.faceTexture = nil
        }
        selectedIndex = min(selectedIndex, rows.count - 1)
    }

    mutating func applyPreset(_ preset: RacePreset) {
        let weight = identity.face.weight
        identity.face = Self.padded(preset.face)
        identity.face.weight = weight
    }

    /// Every slider and part the menu edits, so a short record list reads as zeros.
    static func padded(_ face: PlayerFace) -> PlayerFace {
        var face = face
        face.morphs += Array(repeating: 0, count: max(0, Self.morphCount - face.morphs.count))
        face.parts += Array(repeating: 0, count: max(0, 4 - face.parts.count))
        return face
    }

    public func label(_ row: RaceMenuRow) -> String {
        if row == .name {
            return labels.text("sRSMName")
        }
        return Self.control(for: row).map { labels.text($0.labelKey) } ?? "\(row)"
    }
}
