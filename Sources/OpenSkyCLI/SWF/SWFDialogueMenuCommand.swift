// `swf dialogue-menu`: drives `interface\dialoguemenu.swf` through
// `DialogueMenuMovieBridge` with real DIAL/INFO records and reports what the
// movie built. Rows come straight off the store, skipping selection, because
// the question is whether the movie takes the rows. `--text` prints each field
// from all three string tables. `--probe-rows` publishes empty rows and reports
// which missing-name counts moved.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenus

enum SWFDialogueMenuCommand {
    private static let defaultTicks = 20
    private static let defaultRowCount = 6

    static func run(context: CLIContext, arguments: SWFArguments.DialogueMenu) throws {
        let ticks = try positive(arguments.drive.ticks, name: "--ticks") ?? defaultTicks
        let downCount = try positive(arguments.drive.down, name: "--down") ?? 0
        let rowCount = try positive(arguments.rows, name: "--rows")
            ?? defaultRowCount
        let probeRows = try positive(arguments.probeRows, name: "--probe-rows")
        let wantsText = arguments.text
        let speak = arguments.speak

        let session = try Session(context: context, rowCount: rowCount)
        if wantsText {
            session.printText()
        }

        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: context.makeFileSystem())
                .load(path: DialogueMenuMovieBridge.moviePath)
        )
        DialogueMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        DialogueMenuMovieBridge.activate(runtime: runtime) {}
        for _ in 0 ..< ticks {
            runtime.advance()
        }
        printContract(runtime)

        if let probeRows {
            printRowProbe(runtime, rows: probeRows)
        }

        var model = session.model
        DialogueMenuMovieBridge.publish(model, runtime: runtime)
        settle(runtime)
        printState(runtime, model: model, stage: "published")

        for _ in 0 ..< downCount {
            model.moveSelection(by: 1)
            DialogueMenuMovieBridge.publish(model, runtime: runtime)
            settle(runtime)
        }
        if downCount > 0 {
            printState(runtime, model: model, stage: "navigated")
        }
        if speak, let entry = model.selectedTopic {
            model.beginResponse(info: entry.info, runs: session.runs(of: entry.info))
            DialogueMenuMovieBridge.publish(model, runtime: runtime)
            settle(runtime)
            printState(runtime, model: model, stage: "speaking")
        }
        printDiagnostics(runtime)
    }

    /// Frames a publish needs before the menu's own transitions have settled,
    /// measured: `ShowDialogueList` enters `TRANSITIONING` and the list holder
    /// plays its slide-in before `eMenuState` reaches `TOPIC_LIST_SHOWN`.
    private static let settleTicks = 30

    private static func settle(_ runtime: SWFMovieRuntime) {
        for _ in 0 ..< settleTicks {
            runtime.advance()
        }
    }

    private static func positive(_ text: String?, name: String) throws -> Int? {
        guard let text else { return nil }
        guard let value = Int(text), value >= 0 else {
            throw CLIError.usage("\(name) needs a non-negative integer")
        }
        return value
    }
}

// MARK: - Record session

extension SWFDialogueMenuCommand {
    /// The first player-category topics `Skyrim.esm` declares that have a
    /// response, as menu rows. Nothing is written to the install.
    @MainActor
    private struct Session {
        let strings: LocalizedStrings
        let topics: [(topic: DialogueTopic, info: TopicInfo)]
        let model: DialogueMenuModel

        init(context: CLIContext, rowCount: Int) throws {
            let file = try context.loadSkyrimESM()
            let store = DialogueStore(file: file, pluginName: "Skyrim.esm")
            strings = LocalizedStrings(
                vfs: context.makeFileSystem(), pluginName: "Skyrim.esm"
            )
            let strings = strings
            var picked: [(topic: DialogueTopic, info: TopicInfo)] = []
            for topic in store.sortedTopics() where topic.category == .player {
                guard picked.count < rowCount else { break }
                guard let info = store.infos(for: topic.formID).first else { continue }
                picked.append((topic, info))
            }
            guard !picked.isEmpty else {
                throw CLIError.failure("Skyrim.esm declares no player-category topic")
            }
            topics = picked
            model = DialogueMenuModel(
                speaker: "Speaker",
                speakerKey: nil,
                topics: picked.map { pair in
                    DialogueTopicEntry(
                        info: pair.info.formID,
                        text: DialogueMenuModel.rowText(
                            topic: pair.topic, info: pair.info, strings: strings
                        ),
                        endsConversation: pair.info.flags.contains(.goodbye)
                    )
                }
            )
        }

        func runs(of info: FormID) -> [String] {
            guard let record = topics.first(where: { $0.info.formID == info })?.info else {
                return []
            }
            return DialogueMenuModel.responseRuns(record, strings: strings)
        }

        /// Every text field of every picked row, resolved out of all three
        /// tables, so the table each belongs to is measured rather than
        /// assumed.
        func printText() {
            print("[INFO] swf dialogue-menu text: \(topics.count) topics")
            for pair in topics {
                print("  DIAL \(pair.topic.formID) \(pair.topic.editorID ?? "no editor id")")
                report("    FULL", pair.topic.name)
                report("    RNAM", pair.info.prompt)
                for (index, response) in pair.info.responses.enumerated() {
                    report("    NAM1[\(index)]", response.text)
                }
            }
        }

        private func report(_ label: String, _ value: LString?) {
            guard let value else {
                print("\(label): absent")
                return
            }
            let answers = [StringTable.Kind.strings, .dlstrings, .ilstrings]
                .map { kind in
                    "\(kind): " + (strings.resolve(value, kind: kind).map { "\"\($0)\"" }
                        ?? "none")
                }
            print("\(label): \(answers.joined(separator: " · "))")
        }
    }
}

// MARK: - Reporting

extension SWFDialogueMenuCommand {
    /// What the movie itself declares, before anything is published: the class
    /// constants the engine's state vocabulary is asserted against, the entry
    /// points this bridge drives, and the ones it knowingly does not.
    @MainActor
    private static func printContract(_ runtime: SWFMovieRuntime) {
        let constants = DialogueMenuMovieBridge.stateConstantNames.map { name in
            "\(name)=" + (DialogueMenuMovieBridge.stateConstant(name, runtime: runtime)
                .map(String.init) ?? "absent")
        }
        print("[INFO] swf dialogue-menu class: \(constants.joined(separator: " "))")
        let missing = DialogueMenuMovieBridge.missingEntryPoints(runtime: runtime)
        print(
            "[INFO] swf dialogue-menu entry points: "
                + "\(DialogueMenuMovieBridge.requiredEntryPoints.count) required, "
                + "\(missing.count) missing"
                + (missing.isEmpty ? "" : " (\(missing.joined(separator: ", ")))")
        )
        print(
            "[INFO] swf dialogue-menu deferred: "
                + DialogueMenuMovieBridge.deferredEntryPoints.joined(separator: ", ")
        )
    }

    @MainActor
    private static func printState(
        _ runtime: SWFMovieRuntime,
        model: DialogueMenuModel,
        stage: String
    ) {
        let labels = DialogueMenuMovieBridge.topicLabels(runtime: runtime)
        print("[INFO] swf dialogue-menu \(stage): \(labels.count) movie rows")
        for (index, label) in labels.enumerated() {
            print("  \(index): \(label)")
        }
        let selected = DialogueMenuMovieBridge.selectedIndex(runtime: runtime)
        print(
            "  selection: movie \(selected.map(String.init) ?? "none") · "
                + "engine \(model.selectedIndex)"
        )
        let speaker = DialogueMenuMovieBridge.speakerNameText(runtime: runtime) ?? ""
        print("  speaker: movie \"\(speaker)\" · engine \"\(model.speaker)\"")
        let subtitle = DialogueMenuMovieBridge.subtitleText(runtime: runtime) ?? ""
        print("  subtitle: movie \"\(subtitle)\" · engine \"\(model.subtitle ?? "")\"")
        print(
            "  state: engine \(model.state) · movie eMenuState "
                + (DialogueMenuMovieBridge.menuState(runtime: runtime).map(String.init)
                    ?? "absent")
                + " · holder frame "
                + (DialogueMenuMovieBridge.holderFrameLabel(runtime: runtime) ?? "unlabelled")
        )
    }

    /// Publishes rows with no fields at all and reports which missing-name
    /// counts moved. Every property the movie reads off a row it was handed
    /// lands in that tally, so the delta *is* the row's field list.
    @MainActor
    private static func printRowProbe(_ runtime: SWFMovieRuntime, rows: Int) {
        let before = runtime.tally.missingNames
        DialogueMenuMovieBridge.publish(
            rows: Array(repeating: [:], count: rows),
            atPath: DialogueMenuMovieBridge.topicListPath,
            runtime: runtime
        )
        runtime.callMovie(
            DialogueMenuMovieBridge.invalidateMethod,
            atPath: DialogueMenuMovieBridge.topicListPath,
            arguments: []
        )
        runtime.advance()
        let moved: [(name: String, delta: Int)] = runtime.tally.missingNames
            .map { (name: $0.key, delta: $0.value - (before[$0.key] ?? 0)) }
            .filter { $0.delta > 0 }
            .sorted { lhs, rhs in
                lhs.delta == rhs.delta ? lhs.name < rhs.name : lhs.delta > rhs.delta
            }
        print(
            "[INFO] swf dialogue-menu probe-rows: \(rows) empty rows, "
                + "\(moved.count) names moved"
        )
        for entry in moved {
            print("  \(entry.name) +\(entry.delta)")
        }
    }

    @MainActor
    private static func printDiagnostics(_ runtime: SWFMovieRuntime) {
        let diagnostics = DialogueMenuMovieBridge.diagnostics(runtime: runtime)
        let nodes = runtime.nodeCount
        let opcodes = runtime.tally.unimplementedOpcodes.count
        let invokes = runtime.invokeLog.total
        let line = "[INFO] swf dialogue-menu diagnostics: \(nodes) nodes, "
            + "\(diagnostics.faults) faults, \(opcodes) unimplemented opcodes, "
            + "\(diagnostics.unhandledInvokes) unhandled of \(invokes) invokes, "
            + "\(diagnostics.missingNames) distinct missing names"
        print(line)
        let ranked: [(name: String, count: Int)] = runtime.tally.missingNames
            .map { (name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
            }
        for entry in ranked {
            print("  \(entry.name) \(entry.count)")
        }
        for entry in runtime.invokeLog.entries where !entry.isHandled {
            print("  unhandled \(entry.direction.rawValue) \(entry.name)(\(entry.arguments))")
        }
    }
}
