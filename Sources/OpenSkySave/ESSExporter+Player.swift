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
import OpenSkyWorldState

nonisolated extension ESSExporter {
    var playerDelta: ReferenceStateDelta? {
        contents.snapshot.entries.first { $0.key == .player }?.delta
    }

    mutating func exportPlayer() throws(ESSExportError) {
        var base = ESSActorBaseChange(form: ESSActorBaseChange.playerBase)
        if let identity = playerDelta?.component(PlayerIdentityState.self) {
            exportIdentity(identity, into: &base)
        } else {
            report.update("player") { $0.drop("no player identity") }
        }
        if let spellbook = playerDelta?.component(SpellbookState.self) {
            exportSpells(spellbook, into: &base)
        }
        if let factions = playerDelta?.component(ActorFactionState.self) {
            exportFactions(factions, into: &base)
        }
        try changeForms.append(Self.encode { () throws(ESSError) in try base.changeForm() })
        if let progress = playerDelta?.component(PlayerProgressState.self), !progress.isEmpty {
            report.update("player") { category in
                category.written += 1
                category.drop("perk points, attribute picks, and skill counts (not in the save)")
            }
        }
        exportPlace()
    }

    private mutating func exportIdentity(
        _ identity: PlayerIdentityState, into base: inout ESSActorBaseChange
    ) {
        base.race = forms.ref(loadOrder: identity.race)
        base.isFemale = identity.isFemale
        base.name = identity.name
        let face = identity.face
        base.face = ESSFace(
            hairColor: face.hairColor.flatMap { forms.ref(loadOrder: $0) } ?? ESSRefID(raw: 0),
            headParts: face.headParts.compactMap { forms.ref(loadOrder: $0) },
            morphs: face.morphs, presets: face.parts
        )
        report.update("player") { category in
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

    private mutating func exportSpells(
        _ spellbook: SpellbookState, into base: inout ESSActorBaseChange
    ) {
        var spells: [ESSRefID] = []
        for key in spellbook.known {
            guard let ref = forms.ref(key) else {
                report.update("player") { $0.drop("spell from a plugin not loaded") }
                continue
            }
            spells.append(ref)
        }
        base.spells = spells
        base.leveledSpells = []
        base.shouts = []
        report.update("player") { category in
            category.written += spells.count
            category.drop("read books", count: spellbook.readBooks.count)
            category.drop("greater power cooldowns", count: spellbook.powerDays.count)
        }
    }

    private mutating func exportFactions(
        _ state: ActorFactionState, into base: inout ESSActorBaseChange
    ) {
        var ranks: [ESSFactionRank] = []
        for membership in state.memberships {
            guard let ref = forms.ref(membership.faction) else {
                report.update("player") { $0.drop("faction from a plugin not loaded") }
                continue
            }
            ranks.append(ESSFactionRank(faction: ref, rank: membership.rank))
        }
        base.factions = ranks
        report.update("player") { $0.written += ranks.count }
    }

    /// The player's reference carries the facing and the inventory; the location table
    /// carries the cell.
    private mutating func exportPlace() {
        var player = ESSReferenceChange(form: ESSRefID(kind: .default, value: 0x14), isActor: true)
        if let inventory = playerDelta?.component(ReferenceInventoryState.self) {
            player.inventory = inventoryChanges(inventory, key: .player)
        }
        guard let place = contents.playerPlace, let space = placeSpace(place) else {
            report.update("player") { $0.drop("no saved place") }
            references[.player] = player
            return
        }
        let heading = Self.heading(fromYaw: place.yaw)
        player.placement = ESSPlacement(
            space: space.ref, position: place.feet, rotation: SIMD3(0, 0, heading)
        )
        references[.player] = player
        let cell = CellCoordinate(containing: place.feet)
        location = ESSPlayerLocation(
            nextObjectID: 0, worldspace: space.isInterior ? ESSRefID(raw: 0) : space.ref,
            cell: space.isInterior ? .zero : SIMD2(cell.x, cell.y), space: space.ref,
            position: place.feet
        )
        report.update("player") { $0.written += 1 }
    }

    /// The camera's yaw counts from +X toward +Y; a placement's z rotation counts
    /// clockwise from +Y, as `NPCYawMath` converts it.
    static func heading(fromYaw yaw: Float) -> Float {
        let heading = (Float.pi / 2 - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        return heading < 0 ? heading + 2 * .pi : heading
    }

    private mutating func placeSpace(
        _ place: SavePlayerPlace
    ) -> (ref: ESSRefID, isInterior: Bool)? {
        switch place.cell {
        case let .interior(cell):
            return forms.ref(loadOrder: cell).map { ($0, true) }
        case .exterior:
            guard
                let name = place.worldspace,
                let worldspace = records.form(editorID: name, signature: "WRLD"),
                let ref = forms.ref(worldspace)
            else { return nil }
            if let id = forms.runtimeFormID(worldspace) {
                visitedWorldspaces = [id]
            }
            playerWorldspace = ref
            return (ref, false)
        }
    }

    func fileHeader(_ picture: ESSScreenshot) -> ESSHeader {
        let identity = playerDelta?.component(PlayerIdentityState.self)
        let progress = playerDelta?.component(PlayerProgressState.self) ?? PlayerProgressState()
        let race = identity.flatMap { forms.loadOrder.resolve($0.race) }
            .flatMap { records.editorID(of: $0) }
        return ESSHeader(
            version: ESSHeader.specialEditionVersion, saveNumber: header.saveNumber,
            playerName: identity?.name ?? contents.summary?.characterName ?? "",
            playerLevel: UInt32(clamping: progress.level),
            playerLocation: contents.summary?.locationName ?? "", gameDate: header.gameDate,
            playerRaceEditorID: race ?? contents.summary?.raceName ?? "",
            isFemale: identity?.isFemale ?? false, experience: progress.experience,
            experienceForNextLevel: header.experienceForNextLevel,
            fileTime: ESSHeader.fileTime(of: header.savedAt),
            screenshotWidth: picture.width, screenshotHeight: picture.height, compression: .lz4
        )
    }
}
