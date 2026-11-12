// The player's part of an import: identity and face from the base `NPC_` change, level
// and experience from the header, spells and factions, and the saved place.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

nonisolated extension ESSPlayerImport {
    func importPlayer() {
        let base = playerBase()
        importIdentity(base)
        importer.add(
            PlayerProgressState(
                level: Int(importer.file.header.playerLevel),
                experience: importer.file.header.experience
            ),
            to: .player
        )
        importer.report.update("player") { category in
            category.imported += 1
            category.skip("perk points, skills, and perks (actor data is undocumented)")
        }
        if let base {
            importSpells(base)
            importFactions(base)
        }
        importPlacement()
    }

    private func playerBase() -> ESSActorBaseChange? {
        let form = importer.file.changeForms.first {
            $0.type?.signature == "NPC_" && $0.form == ESSActorBaseChange.playerBase
        }
        return form.flatMap { element in attempt { try ESSActorBaseChange(element) } }
    }

    private func importIdentity(_ base: ESSActorBaseChange?) {
        let race = base?.race.flatMap { race in
            attempt { try importer.form(race, signature: ["RACE"]).get() }
        }
            ?? importer.records.race(editorID: importer.file.header.playerRaceEditorID)
        guard let race, let raceID = importer.mapping.currentFormID(race) else {
            let missing = "race \(importer.file.header.playerRaceEditorID) not found"
            importer.report.update("player") { $0.drop(missing) }
            return
        }
        let identity = PlayerIdentityState(
            race: raceID, isFemale: base?.isFemale ?? importer.file.header.isFemale,
            name: importer.file.header.playerName, face: face(base?.face)
        )
        importer.add(identity, to: .player)
        importer.report.update("player") { category in
            category.imported += 1
            category.skip("face tint layers (not in the save's face block)")
        }
    }

    private func face(_ face: ESSFace?) -> PlayerFace {
        guard let face else { return PlayerFace() }
        return PlayerFace(
            morphs: face.morphs, parts: face.presets,
            headParts: face.headParts.compactMap(currentFormID),
            hairColor: currentFormID(face.hairColor)
        )
    }

    func currentFormID(_ ref: ESSRefID) -> FormID? {
        guard case let .form(form) = importer.mapping.resolve(ref) else { return nil }
        return importer.mapping.currentFormID(form)
    }

    private func importSpells(_ base: ESSActorBaseChange) {
        var known: [ReferenceKey] = []
        for spell in base.spells ?? [] {
            switch importer.form(spell, signature: ["SPEL"]) {
            case let .success(form): known.append(ReferenceKey(resolved: form))
            case let .failure(reason): importer.report
                .update("player") { $0.drop("spell: \(reason.description)") }
            }
        }
        importer.report.update("player") { category in
            category.imported += known.count
            category.drop(
                "shout (OpenSky keeps no known-shout list)",
                count: base.shouts?.count ?? 0
            )
            category.drop("leveled spell", count: base.leveledSpells?.count ?? 0)
        }
        guard !known.isEmpty else { return }
        importer.add(SpellbookState(known: known), to: .player)
    }

    private func importFactions(_ base: ESSActorBaseChange) {
        var memberships: [ActorFactionMembership] = []
        for entry in base.factions ?? [] {
            switch importer.form(entry.faction, signature: ["FACT"]) {
            case let .success(form):
                memberships.append(
                    ActorFactionMembership(faction: ReferenceKey(resolved: form), rank: entry.rank)
                )
            case let .failure(reason):
                importer.report.update("player") { $0.drop("faction: \(reason.description)") }
            }
        }
        importer.report.update("player") { $0.imported += memberships.count }
        guard !memberships.isEmpty else { return }
        importer.add(ActorFactionState(memberships: memberships), to: .player)
    }

    private func importPlacement() {
        guard let location = attempt({ try importer.file.playerLocation() }) else {
            importer.report.update("player") { $0.skip("player location table") }
            return
        }
        switch importer.form(location.space, signature: ["CELL", "WRLD"]) {
        case let .failure(reason):
            importer.report.update("player") { $0.drop("saved place: \(reason.description)") }
        case let .success(space):
            let isInterior = importer.records.signature(of: space) == "CELL"
            importer.placement = ESSImportedPlacement(
                space: space, isInterior: isInterior,
                spaceEditorID: importer.records.editorID(of: space),
                position: location.position, heading: playerHeading(),
                cell: isInterior ? nil : location.cell
            )
            importer.report.update("player") { $0.imported += 1 }
        }
    }

    private func playerHeading() -> Float? {
        let player = importer.file.changeForms.first {
            $0.form == ESSRefID(kind: .default, value: ESSImporter.playerReference.objectID)
                && $0.type?.signature == "ACHR"
        }
        return player.flatMap { element in attempt { try ESSReferenceChange(element) } }?
            .placement?.rotation.z
    }
}
