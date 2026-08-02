// `swf quest-journal`: drive the Quests page of `interface\quest_journal.swf`
// through `QuestJournalMovieBridge` against a real quest, and report what the
// movie built (M13.5, issue #184).
//
// The bring-up gate for the page's data contract, in the CLI rather than only
// in a test because the real-data XCTest host is unreliable on this machine
// (docs/tools/environment.md). It only parses args and prints; the bridge and
// the model it publishes live in `opensky/UI/` and are unit tested there
// against synthetic fixtures.
//
// `--text` is the measurement mode the contract was pinned with: it resolves
// the quest's FULL, CNAM and NNAM lstrings out of all three string tables and
// prints each, so which table a field belongs to is observed rather than
// assumed. `--probe-rows` publishes rows with no fields at all and prints the
// missing-name delta, which is how the row-field names were measured: every
// property the movie reads off a row it was handed lands in that tally.

import Foundation

enum SWFQuestJournalCommand {
    /// `MGRArniel01`, the M13 target quest: the cheapest journal-visible quest
    /// in vanilla `Skyrim.esm` (2 stages, 1 objective, no conditions), picked
    /// by the issue-#181 census.
    private static let defaultQuest = "MGRArniel01"
    private static let defaultTicks = 20

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let editorID = try scanner.option("--quest") ?? defaultQuest
        let ticks = try positive(scanner.option("--ticks"), name: "--ticks") ?? defaultTicks
        let downCount = try positive(scanner.option("--down"), name: "--down") ?? 0
        let wantsText = scanner.flag("--text")
        let objectiveState = try scanner.option("--objective-state")
        let probeRows = try positive(scanner.option("--probe-rows"), name: "--probe-rows")
        try scanner.finish()

        let session = try Session(
            context: context, editorID: editorID, objectiveState: objectiveState
        )
        if wantsText {
            session.printText()
        }

        let vfs = context.makeFileSystem()
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: vfs)
                .load(path: QuestJournalMovieBridge.moviePath)
        )
        SystemMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        SystemMenuMovieBridge.activate(runtime: runtime) {}
        QuestJournalMovieBridge.activate(runtime: runtime)
        for _ in 0 ..< ticks {
            runtime.advance()
        }
        printPage(runtime)

        if let probeRows {
            printRowProbe(runtime, rows: probeRows)
        }

        var model = session.model
        QuestJournalMovieBridge.publish(model, runtime: runtime)
        runtime.advance()
        printState(runtime, model: model, stage: "published")

        for _ in 0 ..< downCount {
            model.moveSelection(by: 1)
            QuestJournalMovieBridge.publish(model, runtime: runtime)
            runtime.advance()
        }
        if downCount > 0 {
            printState(runtime, model: model, stage: "navigated")
        }
        printDiagnostics(runtime)
    }

    private static func positive(_ text: String?, name: String) throws -> Int? {
        guard let text else { return nil }
        guard let value = Int(text), value >= 0 else {
            throw CLIError.usage("\(name) needs a non-negative integer")
        }
        return value
    }
}

// MARK: - Quest session

extension SWFQuestJournalCommand {
    /// One quest started and walked to its last stage, with every objective
    /// displayed, so the page has something to show. Nothing is written to the
    /// install: the state lives in an in-memory `WorldStateStore`.
    @MainActor
    private struct Session {
        let quest: Quest
        let strings: LocalizedStrings
        let runtime: QuestRuntime
        let model: JournalMenuModel

        init(context: CLIContext, editorID: String, objectiveState: String?) throws {
            let file = try context.loadSkyrimESM()
            let store = QuestStore(file: file, pluginName: "Skyrim.esm")
            guard let quest = store.quest(editorID: editorID) else {
                throw CLIError.failure("Skyrim.esm defines no quest \"\(editorID)\"")
            }
            self.quest = quest
            strings = LocalizedStrings(
                vfs: context.makeFileSystem(), pluginName: "Skyrim.esm"
            )
            let quests = QuestRuntime(store: WorldStateStore(), quests: store)
            runtime = quests
            _ = try? quests.startQuest(quest.formID)
            for stage in quest.stages.map(\.index).sorted() {
                _ = try? quests.setStage(stage, on: quest.formID)
            }
            for objective in quest.objectives.map(\.index) {
                _ = try? quests.setObjectiveDisplayed(objective, true, on: quest.formID)
                switch objectiveState {
                case "completed":
                    _ = try? quests.setObjectiveCompleted(objective, true, on: quest.formID)
                case "failed":
                    _ = try? quests.setObjectiveFailed(objective, true, on: quest.formID)
                default:
                    break
                }
            }
            var built = JournalMenuModel.build(
                runtime: quests,
                strings: strings,
                aliases: QuestAliasNaming.none
            )
            // Every start-game-enabled quest is running, so the target quest is
            // one row among many; select it rather than whatever sorts first.
            if let row = built.entries.firstIndex(where: { $0.formID == quest.formID }) {
                built.select(row)
            }
            model = built
        }

        /// Every lstring the page shows, resolved out of all three tables, so
        /// the table a field belongs to stays a measurement.
        func printText() {
            print(
                "[INFO] swf quest-journal text: \(quest.editorID ?? "-") "
                    + "\(quest.formID.description), \(quest.kind.name), "
                    + "\(quest.stages.count) stages, \(quest.objectives.count) objectives, "
                    + "\(quest.aliases.count) aliases"
            )
            printTables("FULL", quest.name)
            for stage in quest.journalStages {
                printTables("stage \(stage.index) CNAM", stage.primaryLogEntry?.text)
            }
            for objective in quest.objectives {
                printTables("objective \(objective.index) NNAM", objective.displayText)
            }
            for alias in quest.aliases {
                print(
                    "[INFO]   alias \(alias.id) \"\(alias.name ?? "-")\" "
                        + "\(alias.fillType.name)"
                )
            }
        }

        private func printTables(_ label: String, _ text: LString?) {
            let kinds: [(String, StringTable.Kind)] = [
                ("strings", .strings), ("dlstrings", .dlstrings), ("ilstrings", .ilstrings)
            ]
            let resolved = kinds.map { name, kind in
                "\(name)=\(strings.resolve(text, kind: kind).map { "\"\($0)\"" } ?? "-")"
            }
            print("[INFO]   \(label): \(resolved.joined(separator: " "))")
        }
    }
}

// MARK: - Reporting

extension SWFQuestJournalCommand {
    private static func printPage(_ runtime: SWFMovieRuntime) {
        let measured = QuestJournalMovieBridge.measuredQuestsTabIndex(runtime: runtime)
        print(
            "[INFO] swf quest-journal page: QuestJournalBase.PAGE_QUEST = "
                + "\(measured.map(String.init) ?? "unregistered"), "
                + "bridge uses \(QuestJournalMovieBridge.questsTabIndex), "
                + "frontmost \(QuestJournalMovieBridge.isFrontmost(runtime: runtime))"
        )
    }

    private static func printState(
        _ runtime: SWFMovieRuntime,
        model: JournalMenuModel,
        stage: String
    ) {
        let quests = QuestJournalMovieBridge.questLabels(runtime: runtime)
        let objectives = QuestJournalMovieBridge.objectiveLabels(runtime: runtime)
        print(
            "[INFO] swf quest-journal \(stage): \(quests.count) movie quest rows, "
                + "\(objectives.count) movie objective rows, engine has "
                + "\(model.entries.count) and \(model.selectedEntry?.objectives.count ?? 0)"
        )
        print("[INFO]   movie quests: \(quests.joined(separator: " | "))")
        print("[INFO]   movie objectives: \(objectives.joined(separator: " | "))")
        let selected = QuestJournalMovieBridge.selectedIndex(
            runtime: runtime, atPath: QuestJournalMovieBridge.titleListPath
        )
        print(
            "[INFO]   movie selection: \(selected.map(String.init) ?? "none"), "
                + "engine selection: \(model.selectedIndex) "
                + "(\(model.selectedEntry?.title ?? "none"))"
        )
        print(
            "[INFO]   movie title field: "
                + "\(QuestJournalMovieBridge.titleText(runtime: runtime) ?? "-")"
        )
        print(
            "[INFO]   movie description field: "
                + "\(QuestJournalMovieBridge.descriptionText(runtime: runtime) ?? "-")"
        )
        for entry in model.selectedEntry?.logEntries ?? [] {
            print("[INFO]   engine log entry: \(entry)")
        }
        printObjectiveFrames(runtime)
    }

    /// Publishes rows carrying no fields at all and reports which missing-API
    /// names moved. This is how the row-field contract was measured: a property
    /// the list reads off a row it was handed and does not find lands in the
    /// tally, and a count that moved during the rebuild names one of them.
    private static func printRowProbe(_ runtime: SWFMovieRuntime, rows: Int) {
        let before = runtime.tally.missingNames
        for path in [
            QuestJournalMovieBridge.titleListPath,
            QuestJournalMovieBridge.objectiveListPath
        ] {
            QuestJournalMovieBridge.publish(
                rows: Array(repeating: [:], count: rows), atPath: path, runtime: runtime
            )
            QuestJournalMovieBridge.invalidate(atPath: path, runtime: runtime)
        }
        runtime.advance()
        // Counts rather than names: every name the rows are asked for is one
        // the movie has usually already asked something else for, so a set
        // difference would report nothing.
        var moved: [(name: String, delta: Int)] = []
        for (name, count) in runtime.tally.missingNames {
            let delta = count - (before[name] ?? 0)
            if delta > 0 {
                moved.append((name: name, delta: delta))
            }
        }
        moved.sort { $0.delta == $1.delta ? $0.name < $1.name : $0.delta > $1.delta }
        print(
            "[INFO] swf quest-journal probe-rows: \(rows) empty rows per list, "
                + "\(moved.count) missing names moved"
        )
        for (name, delta) in moved {
            print("[INFO]   \(name) +\(delta)")
        }
        printObjectiveFrames(runtime)
    }

    private static func printObjectiveFrames(_ runtime: SWFMovieRuntime) {
        let frames = QuestJournalMovieBridge.objectiveEntryFrames(runtime: runtime)
        print(
            "[INFO]   objective entry frames: \(frames.joined(separator: ", "))"
        )
    }

    private static func printDiagnostics(_ runtime: SWFMovieRuntime) {
        let diagnostics = QuestJournalMovieBridge.diagnostics(runtime: runtime)
        print(
            "[INFO] swf quest-journal diagnostics: \(runtime.nodeCount) nodes, "
                + "\(diagnostics.faults) faults, "
                + "\(runtime.tally.unimplementedTotal) unimplemented opcodes, "
                + "\(diagnostics.unhandledInvokes) unhandled of "
                + "\(runtime.invokeLog.total) invokes, "
                + "\(diagnostics.missingNames) distinct missing names"
        )
        for entry in runtime.tally.rankedMissing.prefix(20) {
            print("[INFO]   missing \(entry.name) \(entry.count)")
        }
        for entry in runtime.invokeLog.entries where !entry.isHandled {
            print("[INFO]   unhandled \(entry.direction.rawValue) \(entry.name)")
        }
    }
}
