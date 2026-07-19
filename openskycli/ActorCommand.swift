// `actor`: list ACHR placed actors around one exterior cell, resolve each
// base NPC_ through its TPLT template chain (milestone 5.1), then resolve
// visuals — skeleton, skin/outfit body parts with slot masking, FaceGen
// paths (milestone 5.2). WRLD tree walk mirrors CellCommand; persistent-cell
// ACHRs map in by physical position like door handling. Resolution + policy
// live in ActorTemplateResolver / ActorVisualResolver (opensky/World/);
// this file only parses args and prints.

import Foundation

enum ActorCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let npc = try scanner.option("--npc")
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(scanner.option("--x"), name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(scanner.option("--y"), name: "--y") ?? FirstRenderCell.gridY
        let radius = try int32(scanner.option("--radius"), name: "--radius") ?? 1
        guard radius >= 0 else {
            throw CLIError.usage("--radius expects a non-negative integer")
        }
        try scanner.finish()

        let file = try context.loadSkyrimESM()
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        if let npc {
            try reportNamed(npc, file: file, localized: localized)
            return
        }
        guard let world = worldChildren(editorID: worldspace, file: file, localized: localized)
        else {
            throw CLIError.failure("worldspace \(worldspace) not found")
        }
        let resolver = ActorTemplateResolver.build(from: file, localized: localized)
        let visualResolver = ActorVisualResolver.build(
            from: file, localized: localized, pluginName: "Skyrim.esm"
        )
        print("[INFO] actor probe — \(worldspace) (\(gridX),\(gridY)) radius \(radius), "
            + "indexes: \(resolver.actors.count) NPC_, \(resolver.leveledActors.count) LVLN, "
            + "\(visualResolver.races.count) RACE, \(visualResolver.armors.count) ARMO, "
            + "\(visualResolver.armorAddons.count) ARMA, \(visualResolver.outfits.count) OTFT, "
            + "\(visualResolver.leveledItems.count) LVLI")

        let collection = collectActors(
            world: world,
            gridX: gridX,
            gridY: gridY,
            radius: radius,
            localized: localized
        )
        var resolved = 0
        var failed = 0
        let ordered = collection.actors
            .sorted { $0.actor.formID.rawValue < $1.actor.formID.rawValue }
        for placed in ordered {
            if report(placed, resolver: resolver, visualResolver: visualResolver) {
                resolved += 1
            } else {
                failed += 1
            }
        }
        print("[INFO] \(collection.actors.count) ACHRs discovered: \(resolved) resolved, "
            + "\(failed) failed"
            + (collection.deleted > 0 ? ", \(collection.deleted) deleted skipped" : "")
            + (collection.malformed > 0 ? ", \(collection.malformed) malformed" : ""))
    }

    // MARK: - Named NPC_ resolution (--npc)

    /// Resolves one base NPC_ by FormID or editor ID without needing a
    /// placed ACHR — named residents live in interior home cells, so the
    /// exterior walk cannot reach them.
    private static func reportNamed(
        _ key: String,
        file: ESMFile,
        localized: Bool
    ) throws {
        let resolver = ActorTemplateResolver.build(from: file, localized: localized)
        let visualResolver = ActorVisualResolver.build(
            from: file, localized: localized, pluginName: "Skyrim.esm"
        )
        let base: FormID
        if let raw = UInt32(key, radix: 16), resolver.actors[raw] != nil {
            base = FormID(raw)
        } else if let match = resolver.actors.values.first(where: { $0.editorID == key }) {
            base = match.formID
        } else {
            throw CLIError.failure("no NPC_ record matches \(key)")
        }
        let editorID = resolver.actors[base.rawValue]?.editorID ?? "?"
        print("NPC_ \(base) \"\(editorID)\"")
        do {
            let appearance = try resolver.resolve(base: base)
            print("  chain: \(chainDescription(appearance.chain))")
            print("  female \(describe(appearance.isFemale))"
                + "; race \(describe(appearance.race))"
                + "; skin \(describe(appearance.wornArmor))"
                + "; head parts \(describeParts(appearance.headParts))"
                + "; outfit \(describe(appearance.defaultOutfit))")
            let visual = try visualResolver.resolve(appearance: appearance)
            printVisual(visual)
        } catch let error as ActorResolveError {
            throw CLIError.failure("unresolved: \(describe(error))")
        } catch let error as ActorVisualError {
            throw CLIError.failure("visual unresolved: \(describe(error))")
        }
    }
}

// MARK: - Reporting

extension ActorCommand {
    /// Prints one ACHR block; returns whether template + visual resolution
    /// both succeeded.
    private static func report(
        _ placed: LocatedActor,
        resolver: ActorTemplateResolver,
        visualResolver: ActorVisualResolver
    ) -> Bool {
        let actor = placed.actor
        let position = actor.placement.position
        let editorID = resolver.actors[actor.base.rawValue]?.editorID ?? "?"
        print("ACHR \(actor.formID) base \(actor.base) \"\(editorID)\" "
            + "cell (\(placed.coordinate.x),\(placed.coordinate.y))"
            + (placed.isPersistent ? " persistent" : "")
            + " at (\(position.x), \(position.y), \(position.z)) scale \(actor.scale)")
        do {
            let appearance = try resolver.resolve(base: actor.base)
            print("  chain: \(chainDescription(appearance.chain))")
            print("  female \(describe(appearance.isFemale))"
                + "; race \(describe(appearance.race))"
                + "; skin \(describe(appearance.wornArmor))"
                + "; head parts \(describeParts(appearance.headParts))"
                + "; outfit \(describe(appearance.defaultOutfit))")
            let visual = try visualResolver.resolve(appearance: appearance)
            printVisual(visual)
            return true
        } catch let error as ActorResolveError {
            print("  [WARNING] unresolved: \(describe(error))")
            return false
        } catch let error as ActorVisualError {
            print("  [WARNING] visual unresolved: \(describe(error))")
            return false
        } catch {
            print("  [WARNING] unresolved: \(error)")
            return false
        }
    }

    private static func printVisual(_ visual: ResolvedActorVisual) {
        print("  skeleton \(visual.skeletonPath ?? "-")")
        for part in visual.parts {
            print("  part \(describe(part.origin)) arma \(part.armature) "
                + "slots 0x\(String(format: "%08X", part.slots.rawValue)) \(part.modelPath)")
        }
        print("  facegen \(visual.faceGenMeshPath ?? "-")")
        if !visual.skips.isEmpty {
            print("  skips: \(visual.skips.map(describe).joined(separator: ", "))")
        }
    }

    private static func chainDescription(_ chain: [ActorChainLink]) -> String {
        chain.map { link in
            switch link {
            case let .npc(formID):
                "NPC_ \(formID)"
            case let .leveled(list, chosen):
                "LVLN \(list) [chose \(chosen)]"
            }
        }.joined(separator: " -> ")
    }

    private static func describe(_ field: ActorSourcedField<Bool>) -> String {
        "\(field.value) (from \(field.source))"
    }

    private static func describe(_ field: ActorSourcedField<FormID?>) -> String {
        "\(field.value.map(String.init(describing:)) ?? "-") (from \(field.source))"
    }

    private static func describeParts(_ field: ActorSourcedField<[FormID]>) -> String {
        let parts = field.value.isEmpty
            ? "-"
            : field.value.map(String.init(describing:)).joined(separator: "+")
        return "\(parts) (from \(field.source))"
    }

    private static func describe(_ origin: ResolvedBodyPart.Origin) -> String {
        switch origin {
        case let .skin(armor):
            "skin \(armor)"
        case let .outfit(armor):
            "outfit \(armor)"
        }
    }

    private static func describe(_ skip: AppearanceSkip) -> String {
        "\(skip.reason) \(skip.subject)"
    }

    private static func describe(_ error: ActorVisualError) -> String {
        switch error {
        case let .missingRace(race, npc):
            "missing race \(race.map(String.init(describing:)) ?? "-") for NPC_ \(npc)"
        case let .missingSkin(skin, npc):
            "missing skin \(skin.map(String.init(describing:)) ?? "-") for NPC_ \(npc)"
        case let .brokenOutfitChain(outfit, item, reason):
            "broken outfit chain OTFT \(outfit)"
                + (item.map { " at \($0)" } ?? "")
                + " (\(reason))"
        }
    }

    private static func describe(_ error: ActorResolveError) -> String {
        switch error {
        case let .missingTarget(formID, referencedBy):
            "missing target \(formID)"
                + (referencedBy.map { " (referenced by \($0))" } ?? "")
        case let .cycle(chain):
            "template cycle "
                + chain.map(String.init(describing:)).joined(separator: " -> ")
        case let .emptyLeveledList(formID, referencedBy):
            "empty leveled list \(formID)"
                + (referencedBy.map { " (referenced by \($0))" } ?? "")
        }
    }

    // MARK: - ACHR collection

    private struct LocatedActor {
        let actor: PlacedActor
        let coordinate: CellCoordinate
        let isPersistent: Bool
    }

    private struct Collection {
        var actors: [LocatedActor] = []
        var deleted = 0
        var malformed = 0
    }

    /// ACHRs from every cell in the radius plus the worldspace persistent
    /// cell at (0,0), persistent placements mapped to cells by position and
    /// deduplicated by FormID (door-handling pattern).
    private static func collectActors(
        world: ESMGroup,
        gridX: Int32,
        gridY: Int32,
        radius: Int32,
        localized: Bool
    ) -> Collection {
        var collection = Collection()
        var byID: [UInt32: LocatedActor] = [:]
        for offsetY in -radius ... radius {
            for offsetX in -radius ... radius {
                let x = gridX + offsetX
                let y = gridY + offsetY
                guard let found = findCell(in: world, x: x, y: y, localized: localized)
                else { continue }
                forEachActor(in: found.children, counting: &collection) { actor in
                    byID[actor.formID.rawValue] = LocatedActor(
                        actor: actor,
                        coordinate: CellCoordinate(x: x, y: y),
                        isPersistent: false
                    )
                }
            }
        }
        // Worldspace persistent refs are stored at grid (0,0); physical
        // position decides which streamed cell owns them.
        if let persistent = findCell(in: world, x: 0, y: 0, localized: localized) {
            forEachActor(in: persistent.children, counting: &collection) { actor in
                let coordinate = CellGridManager.cellCoordinate(for: actor.placement.position)
                guard
                    abs(coordinate.x - gridX) <= radius,
                    abs(coordinate.y - gridY) <= radius
                else { return }
                byID[actor.formID.rawValue] = LocatedActor(
                    actor: actor,
                    coordinate: coordinate,
                    isPersistent: true
                )
            }
        }
        collection.actors = Array(byID.values)
        return collection
    }

    private static func forEachActor(
        in cellChildren: ESMGroup?,
        counting collection: inout Collection,
        _ body: (PlacedActor) -> Void
    ) {
        guard let cellChildren, let children = try? cellChildren.children() else { return }
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren
                || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            for case let .record(record) in records where record.type == "ACHR" {
                guard !record.isDeleted else {
                    collection.deleted += 1
                    continue
                }
                do {
                    try body(PlacedActor(record: record))
                } catch {
                    collection.malformed += 1
                }
            }
        }
    }
}

// MARK: - WRLD tree walk (read-only mirror of CellCommand)

extension ActorCommand {
    private static func worldChildren(
        editorID: String,
        file: ESMFile,
        localized: Bool
    ) -> ESMGroup? {
        guard let top = file.topGroup(of: "WRLD"), let children = try? top.children() else {
            return nil
        }
        var matchedFormID: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = try? Worldspace(record: record, localized: localized)
                matchedFormID = world?.editorID == editorID ? record.formID : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matchedFormID:
                return group
            default:
                break
            }
        }
        return nil
    }

    private struct FoundCell {
        let formID: UInt32
        let children: ESMGroup?
    }

    private static func findCell(
        in group: ESMGroup,
        x: Int32,
        y: Int32,
        localized: Bool
    ) -> FoundCell? {
        guard let children = try? group.children() else { return nil }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: localized),
                    let grid = cell.grid, grid.x == x, grid.y == y
                else { continue }
                let cellChildren = cellChildren(
                    following: index, in: children, formID: record.formID
                )
                return FoundCell(formID: record.formID, children: cellChildren)
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                if let found = findCell(in: sub, x: x, y: y, localized: localized) {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    private static func cellChildren(
        following index: Int,
        in children: [ESMGroup.Child],
        formID: UInt32
    ) -> ESMGroup? {
        for case let .group(sub) in children[(index + 1)...] where sub.kind == .cellChildren {
            if sub.parentFormID == formID {
                return sub
            }
        }
        return nil
    }

    private static func int32(_ value: String?, name: String) throws -> Int32? {
        guard let value else { return nil }
        guard let parsed = Int32(value) else {
            throw CLIError.usage("\(name) expects an integer, got \(value)")
        }
        return parsed
    }
}
