// Each race menu row as a number: its range, its value now, and what a new value
// does to the face. A choice row counts its options from 0; for a beard, scars,
// complexion, war paint, and dirt, 0 is none. See docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension RaceMenuModel {
    /// Head part types that may be left off.
    static let optionalParts: Set<HeadPart.PartType> = [.facialHair, .scar]

    /// The slider's bounds and step; nil for a row without a slider.
    public func range(_ row: RaceMenuRow) -> (bounds: ClosedRange<Float>, step: Float)? {
        func choices(_ count: Int) -> (bounds: ClosedRange<Float>, step: Float) {
            (0 ... Float(max(count - 1, 0)), 1)
        }
        switch row {
        case .race, .name: return nil
        case .sex: return choices(2)
        case .weight: return (0 ... 100, 5)
        case .slider: return (-1 ... 1, Self.sliderStep)
        case let .part(index):
            guard let range = Self.partRanges[index] else { return nil }
            return (Float(range.lowerBound) ... Float(range.upperBound), 1)
        case .headPreset: return choices(options.presets.count)
        case let .headPart(type):
            let count = options.headParts[type]?.count ?? 0
            return choices(count + (Self.optionalParts.contains(type) ? 1 : 0))
        case .hairColor: return choices(options.hairColors.count)
        case .complexion: return choices(options.complexions.count + 1)
        case let .tintColor(type): return choices(activeMask(type)?.colors.count ?? 0)
        case let .tintMask(type): return choices(options.masks(ofType: type).count + 1)
        }
    }

    /// The row's position now, in the units of `range`.
    public func position(_ row: RaceMenuRow) -> Float {
        let face = identity.face
        switch row {
        case .race, .name: return 0
        case .sex: return identity.isFemale ? 1 : 0
        case .weight: return face.weight
        case let .slider(index): return face.morphs[index]
        case let .part(index): return Float(face.parts[index])
        case .headPreset: return Float(presetIndex)
        case let .headPart(type):
            let list = options.headParts[type] ?? []
            let offset = Self.optionalParts.contains(type) ? 1 : 0
            return Float(list.firstIndex { face.headParts.contains($0) }.map { $0 + offset } ?? 0)
        case .hairColor:
            return Float(options.hairColors.firstIndex { $0.formID == face.hairColor } ?? 0)
        case .complexion:
            return Float(options.complexions.firstIndex { $0 == face.faceTexture }
                .map { $0 + 1 } ?? 0)
        case let .tintColor(type):
            guard let mask = activeMask(type), let layer = layer(of: mask) else { return 0 }
            return Float(mask.colors.firstIndex { $0.color == layer.color } ?? 0)
        case let .tintMask(type):
            let masks = options.masks(ofType: type)
            return Float(masks.firstIndex { layer(of: $0) != nil }.map { $0 + 1 } ?? 0)
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
        case .name:
            return
        default:
            guard let range = range(row) else { return }
            set(row, to: position(row) + Float(delta) * range.step)
        }
    }

    /// A value the movie's slider sent, or a step, clamped to the row's range.
    public mutating func set(_ row: RaceMenuRow, to value: Float) {
        guard value.isFinite, let range = range(row) else { return }
        let value = min(max(value, range.bounds.lowerBound), range.bounds.upperBound)
        let choice = Int(value.rounded())
        switch row {
        case .race, .name: return
        case .sex: identity.isFemale = choice == 1
        case .weight: identity.face.weight = value
        case let .slider(index): identity.face.morphs[index] = (value * 10).rounded() / 10
        case let .part(index): identity.face.parts[index] = Int32(choice)
        default: setChoice(row, choice)
        }
    }

    /// The rows that pick one of the race's options.
    private mutating func setChoice(_ row: RaceMenuRow, _ choice: Int) {
        switch row {
        case .headPreset:
            guard options.presets.indices.contains(choice) else { return }
            presetIndex = choice
            applyPreset(options.presets[choice])
        case let .headPart(type): setHeadPart(type, choice: choice)
        case .hairColor:
            identity.face.hairColor = options.hairColors.indices.contains(choice)
                ? options.hairColors[choice].formID : identity.face.hairColor
        case .complexion:
            identity.face.faceTexture = choice == 0 ? nil : options.complexions[choice - 1]
        case let .tintColor(type):
            guard let mask = activeMask(type), mask.colors.indices.contains(choice) else { return }
            paint(mask, mask.colors[choice])
        case let .tintMask(type): setTintMask(type, choice: choice)
        default: return
        }
    }

    /// The row's value as the readout prints it.
    public func value(_ row: RaceMenuRow) -> String {
        switch row {
        case .race: races.first { $0.formID == identity.race }?.name ?? "\(identity.race)"
        case .sex: identity.isFemale ? "Female" : "Male"
        case .name: identity.name
        case .slider: String(format: "%.1f", position(row))
        default: "\(Int(position(row)))"
        }
    }

    /// The body colour the skin tone layer gives, which an NPC stores as `QNAM`.
    var bodyToneLine: String? {
        guard
            let mask = activeMask(Self.skinToneType), let layer = layer(of: mask)
        else { return nil }
        let tone = PlayerAppearanceOverride.bodySkinTone(
            layer: layer.color, strength: layer.strength
        ) * 255
        return String(format: "Body tone: rgb %.0f %.0f %.0f", tone.x, tone.y, tone.z)
    }

    // MARK: - Face edits

    private mutating func setHeadPart(_ type: HeadPart.PartType, choice: Int) {
        let list = options.headParts[type] ?? []
        identity.face.headParts.removeAll { list.contains($0) }
        let index = choice - (Self.optionalParts.contains(type) ? 1 : 0)
        if list.indices.contains(index) {
            identity.face.headParts.append(list[index])
        }
    }

    private mutating func setTintMask(_ type: UInt16, choice: Int) {
        let masks = options.masks(ofType: type)
        let colorIndex = Int(position(.tintColor(type)))
        identity.face.tints.removeAll { layer in masks.contains { $0.index == layer.maskIndex } }
        guard masks.indices.contains(choice - 1) else { return }
        let mask = masks[choice - 1]
        paint(mask, mask.colors[min(colorIndex, mask.colors.count - 1)])
    }

    private mutating func paint(_ mask: RaceMenuTintMask, _ color: RaceMenuColor) {
        let layer = PlayerTintLayer(
            maskIndex: mask.index, color: color.color, strength: color.strength
        )
        if let index = identity.face.tints.firstIndex(where: { $0.maskIndex == mask.index }) {
            identity.face.tints[index] = layer
        } else {
            identity.face.tints.append(layer)
        }
    }

    /// The mask a colour row paints: the picked one for war paint and dirt, else the
    /// type's first mask.
    func activeMask(_ type: UInt16) -> RaceMenuTintMask? {
        let masks = options.masks(ofType: type)
        guard Self.choiceTintTypes.contains(type) else { return masks.first }
        return masks.first { layer(of: $0) != nil }
    }

    private func layer(of mask: RaceMenuTintMask) -> PlayerTintLayer? {
        identity.face.tints.first { $0.maskIndex == mask.index }
    }
}
