// Decoded views the chargen and map work reads: race chargen data, NPC face
// data, worldspace map data, and map marker data. See docs/formats/actors.md
// and docs/engine/world-map.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension RecordTextDump {
    static func chargenSummary(_ record: ESMRecord, _ localized: Bool) throws -> String? {
        switch record.type {
        case "RACE": try raceChargenText(Race(record: record, localized: localized))
        case "NPC_": try faceText(ActorBase(record: record, localized: localized))
        default: nil
        }
    }

    static func raceChargenText(_ race: Race) -> String {
        let playable = race.flags.contains(.playable) ? "playable" : "not playable"
        let heads = [("male", race.details.headData.male), ("female", race.details.headData.female)]
        let lines = heads.map { sex, head in
            "  \(sex): \(head.presets.count) presets, \(head.headParts.count) head parts, "
                + "\(head.tintMasks.count) tint masks, \(head.hairColors.count) hair colors"
        }
        return (["decoded RACE chargen: \(race.editorID ?? "-"), \(playable)"] + lines)
            .joined(separator: "\n")
    }

    static func faceText(_ actor: ActorBase) -> String {
        let details = actor.details
        let morphs = details.faceMorphs.enumerated()
            .filter { $0.element != 0 }
            .map { String(format: "%d=%.2f", $0.offset, $0.element) }
        let tints = details.tintLayers.map { layer -> String in
            let index = layer.index.map { String($0) } ?? "-"
            let amount = layer.interpolation.map { String($0) } ?? "-"
            return "\(index)@\(amount)"
        }
        let weight = details.weight.map { String($0) } ?? "-"
        let header = "decoded NPC_ face: weight \(weight), \(actor.headParts.count) head parts"
        let morphLine = morphs.isEmpty ? "none" : morphs.joined(separator: " ")
        let partLine = details.faceParts.map(String.init).joined(separator: " ")
        let tintLine = tints.isEmpty ? "none" : tints.joined(separator: " ")
        return [header, "  morphs: \(morphLine)", "  parts: \(partLine)", "  tints: \(tintLine)"]
            .joined(separator: "\n")
    }

    static func mapDataText(_ world: Worldspace) -> String? {
        guard let map = world.details.map else { return nil }
        let size = map.usableDimensions
        let northWest = map.northWestCell
        let southEast = map.southEastCell
        let low = map.cameraMinHeight.map { String($0) } ?? "-"
        let high = map.cameraMaxHeight.map { String($0) } ?? "-"
        let pitch = map.cameraInitialPitch.map { String($0) } ?? "-"
        let cells = "cells (\(northWest.x),\(northWest.y)) to (\(southEast.x),\(southEast.y))"
        return "  map: \(size.x)x\(size.y), \(cells), camera \(low)-\(high) high, pitch \(pitch)"
    }

    static func markerText(_ marker: MapMarker?) -> String {
        guard let marker else { return "" }
        let states = [
            marker.isVisible ? "visible" : "hidden",
            marker.canTravelTo ? "travel" : "no travel"
        ]
        let type = marker.type.map { $0.name ?? "\($0.rawValue)" } ?? "-"
        return "\n  marker: type \(type), " + states.joined(separator: ", ")
    }
}
