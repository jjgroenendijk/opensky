// The player's part of an export: the header, the base `NPC_` change with identity,
// face, spells, and factions, the player's reference with place and inventory, and
// the player location table.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkySaveInterface
import OpenSkyWorldState

nonisolated extension ESSPlayerExport {
    var playerDelta: ReferenceStateDelta? {
        exporter.contents.snapshot.entries.first { $0.key == .player }?.delta
    }

    func exportPlayer() throws(ESSExportError) {
        var base = ESSActorBaseChange(form: ESSActorBaseChange.playerBase)
        if let identity = playerDelta?.component(PlayerIdentityState.self) {
            exportIdentity(identity, into: &base)
        } else {
            exporter.report.update("player") { $0.drop("no player identity") }
        }
        if let spellbook = playerDelta?.component(SpellbookState.self) {
            exportSpells(spellbook, into: &base)
        }
        if let factions = playerDelta?.component(ActorFactionState.self) {
            exportFactions(factions, into: &base)
        }
        try exporter.changeForms
            .append(ESSExporter.encode { () throws(ESSError) in try base.changeForm() })
        if let progress = playerDelta?.component(PlayerProgressState.self), !progress.isEmpty {
            exporter.report.update("player") { category in
                category.written += 1
                category.drop("perk points, attribute picks, and skill counts (not in the save)")
            }
        }
        exportPlace()
    }

    private func exportIdentity(
        _ identity: PlayerIdentityState, into base: inout ESSActorBaseChange
    ) {
        base.race = exporter.forms.ref(loadOrder: identity.race)
        base.isFemale = identity.isFemale
        base.name = identity.name
        let face = identity.face
        base.face = ESSFace(
            hairColor: face.hairColor
                .flatMap { exporter.forms.ref(loadOrder: $0) } ?? ESSRefID(raw: 0),
            headParts: face.headParts.compactMap { exporter.forms.ref(loadOrder: $0) },
            morphs: face.morphs, presets: face.parts
        )
        exporter.report.update("player") { category in
            category.written += 1
            if base.race == nil {
                category.drop("race from a plugin not loaded")
            }
            category.drop("face tint layers (not in the face block)", count: face.tints.count)
            if face.faceTexture != nil {
                category.drop("face texture")
            }
        }
    }

    private func exportSpells(
        _ spellbook: SpellbookState, into base: inout ESSActorBaseChange
    ) {
        var spells: [ESSRefID] = []
        for key in spellbook.known {
            guard let ref = exporter.forms.ref(key) else {
                exporter.report.update("player") { $0.drop("spell from a plugin not loaded") }
                continue
            }
            spells.append(ref)
        }
        base.spells = spells
        base.leveledSpells = []
        base.shouts = []
        exporter.report.update("player") { category in
            category.written += spells.count
            category.drop("read books", count: spellbook.readBooks.count)
            category.drop("greater power cooldowns", count: spellbook.powerDays.count)
        }
    }

    private func exportFactions(
        _ state: ActorFactionState, into base: inout ESSActorBaseChange
    ) {
        var ranks: [ESSFactionRank] = []
        for membership in state.memberships {
            guard let ref = exporter.forms.ref(membership.faction) else {
                exporter.report.update("player") { $0.drop("faction from a plugin not loaded") }
                continue
            }
            ranks.append(ESSFactionRank(faction: ref, rank: membership.rank))
        }
        base.factions = ranks
        exporter.report.update("player") { $0.written += ranks.count }
    }

    /// The player's reference carries the facing and the inventory; the location table
    /// carries the cell.
    private func exportPlace() {
        var player = ESSReferenceChange(form: ESSRefID(kind: .default, value: 0x14), isActor: true)
        if let inventory = playerDelta?.component(ReferenceInventoryState.self) {
            player.inventory = ESSReferenceExport(exporter: exporter).inventoryChanges(
                inventory,
                key: .player
            )
        }
        guard let place = exporter.contents.playerPlace, let space = placeSpace(place) else {
            exporter.report.update("player") { $0.drop("no saved place") }
            exporter.references[.player] = player
            return
        }
        let heading = Self.heading(fromYaw: place.yaw)
        player.placement = ESSPlacement(
            space: space.ref, position: place.feet, rotation: SIMD3(0, 0, heading)
        )
        exporter.references[.player] = player
        let cell = CellCoordinate(containing: place.feet)
        exporter.location = ESSPlayerLocation(
            nextObjectID: 0, worldspace: space.isInterior ? ESSRefID(raw: 0) : space.ref,
            cell: space.isInterior ? .zero : SIMD2(cell.x, cell.y), space: space.ref,
            position: place.feet
        )
        exporter.report.update("player") { $0.written += 1 }
    }

    /// The camera's yaw counts from +X toward +Y; a placement's z rotation counts
    /// clockwise from +Y, as `NPCYawMath` converts it.
    static func heading(fromYaw yaw: Float) -> Float {
        let heading = (Float.pi / 2 - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        return heading < 0 ? heading + 2 * .pi : heading
    }

    private func placeSpace(
        _ place: SavePlayerPlace
    ) -> (ref: ESSRefID, isInterior: Bool)? {
        switch place.cell {
        case let .interior(cell):
            return exporter.forms.ref(loadOrder: cell).map { ($0, true) }
        case .exterior:
            guard
                let name = place.worldspace,
                let worldspace = exporter.records.form(editorID: name, signature: "WRLD"),
                let ref = exporter.forms.ref(worldspace)
            else { return nil }
            if let id = exporter.forms.runtimeFormID(worldspace) {
                exporter.visitedWorldspaces = [id]
            }
            exporter.playerWorldspace = ref
            return (ref, false)
        }
    }

    func fileHeader(_ picture: ESSScreenshot) -> ESSHeader {
        let identity = playerDelta?.component(PlayerIdentityState.self)
        let progress = playerDelta?.component(PlayerProgressState.self) ?? PlayerProgressState()
        let race = identity.flatMap { exporter.forms.loadOrder.resolve($0.race) }
            .flatMap { exporter.records.editorID(of: $0) }
        return ESSHeader(
            version: ESSHeader.specialEditionVersion, saveNumber: exporter.header.saveNumber,
            playerName: identity?.name ?? exporter.contents.summary?.characterName ?? "",
            playerLevel: UInt32(clamping: progress.level),
            playerLocation: exporter.contents.summary?.locationName ?? "",
            gameDate: exporter.header.gameDate,
            playerRaceEditorID: race ?? exporter.contents.summary?.raceName ?? "",
            isFemale: identity?.isFemale ?? false, experience: progress.experience,
            experienceForNextLevel: exporter.header.experienceForNextLevel,
            fileTime: ESSHeader.fileTime(of: exporter.header.savedAt),
            screenshotWidth: picture.width, screenshotHeight: picture.height, compression: .lz4
        )
    }
}
