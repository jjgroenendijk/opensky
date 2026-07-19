// `actor`: list ACHR placed actors around one exterior cell and resolve
// each base NPC_ through its TPLT template chain (milestone 5.1) — WRLD
// tree walk mirroring CellCommand, persistent-cell ACHRs mapped in by
// physical position like door handling. Resolution + policy live in
// ActorTemplateResolver (opensky/World/ActorResolution.swift); this file
// only parses args and prints.

import Foundation

enum ActorCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
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
        guard let world = worldChildren(editorID: worldspace, file: file, localized: localized)
        else {
            throw CLIError.failure("worldspace \(worldspace) not found")
        }
        let resolver = ActorTemplateResolver.build(from: file, localized: localized)
        print("[INFO] actor probe — \(worldspace) (\(gridX),\(gridY)) radius \(radius), "
            + "indexes: \(resolver.actors.count) NPC_, \(resolver.leveledActors.count) LVLN")

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
            if report(placed, resolver: resolver) {
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

    // MARK: - Reporting

    /// Prints one ACHR block; returns whether resolution succeeded.
    private static func report(
        _ placed: LocatedActor,
        resolver: ActorTemplateResolver
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
            return true
        } catch let error as ActorResolveError {
            print("  [WARNING] unresolved: \(describe(error))")
            return false
        } catch {
            print("  [WARNING] unresolved: \(error)")
            return false
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
