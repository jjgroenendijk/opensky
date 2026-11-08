// The ordered field walk behind `Scene`. HNAM opens and closes a phase, ALID
// opens an actor, a 2-byte ANAM opens an action and an empty ANAM closes it.
// Inside a phase, NEXT moves from the start conditions to the completion ones.

import Foundation
import OpenSkyFormatsCore

nonisolated struct SceneFieldWalk {
    private enum Mode {
        case top
        case phase(stage: Int)
        case actor
        case action
    }

    var fields: RecordFields
    private var mode = Mode.top
    private(set) var editorID: String?
    private(set) var flags: UInt32 = 0
    private(set) var phases: [ScenePhase] = []
    private(set) var actors: [SceneActor] = []
    private(set) var actions: [SceneAction] = []
    private(set) var quest: FormID?
    private(set) var lastActionIndex: UInt32?
    private(set) var actorBehavior: SceneActorBehavior?
    private(set) var conditions = ConditionList()
    private(set) var scriptData = ScriptData(ownerType: "SCEN")
    private var phase = ScenePhase()
    private var phaseRuns = [ConditionList(), ConditionList()]
    private var action: SceneAction?
    private var dialogue = SceneDialogue()
    private var packages: [FormID] = []
    private var timer: Float?

    init(record: ESMRecord) throws {
        fields = try RecordFields(record: record, type: "SCEN")
    }

    mutating func run() {
        for index in fields.fields.indices {
            if PlacedReferenceDetails.unusedScriptFields.contains(fields.fields[index].type) {
                fields.markUsed(at: index)
                continue
            }
            switch mode {
            case .top:
                topField(at: index)
            case let .phase(stage):
                phaseField(at: index, stage: stage)
            case .actor:
                if !actorField(at: index) {
                    mode = .top
                    topField(at: index)
                }
            case .action:
                actionField(at: index)
            }
        }
        switch mode {
        case .top, .actor: break
        case .phase, .action: fields.note(.mismatch("SCEN run left open at record end"))
        }
    }

    // MARK: - Top level

    private mutating func topField(at index: Int) {
        if !headerField(at: index), !runStart(at: index) {
            let field = fields.fields[index]
            guard ConditionList.isConditionField(field.type) else { return }
            _ = fields.read(at: index) { _ in try conditions.decode(field: field) }
        }
    }

    private mutating func headerField(at index: Int) -> Bool {
        let field = fields.fields[index]
        switch field.type {
        case "EDID": editorID = fields.read(at: index) { try $0.readZString() }
        case "VMAD": _ = fields.read(at: index) { _ in try scriptData.decode(field: field) }
        case "FNAM": flags = fields.read(at: index) { try $0.readUInt32() } ?? 0
        case "NEXT": fields.markUsed(at: index)
        case "PNAM": quest = fields.read(at: index) { try $0.readFormID() }?.nonNull
        case "INAM": lastActionIndex = fields.read(at: index) { try $0.readUInt32() }
        case "VNAM": actorBehavior = fields.read(at: index) { try SceneActorBehavior(&$0) }
        default: return false
        }
        return true
    }

    private mutating func runStart(at index: Int) -> Bool {
        switch fields.fields[index].type {
        case "HNAM":
            fields.markUsed(at: index)
            phase = ScenePhase()
            phaseRuns = [ConditionList(), ConditionList()]
            mode = .phase(stage: 0)
        case "ALID":
            guard let alias = fields.read(at: index, { try $0.readInt32() }) else { return true }
            actors.append(SceneActor(aliasID: alias))
            mode = .actor
        case "ANAM":
            guard let type = fields.read(at: index, { try $0.readUInt16() }) else { return true }
            action = SceneAction(type: type, payload: .unknown)
            dialogue = SceneDialogue()
            packages = []
            timer = nil
            mode = .action
        default:
            return false
        }
        return true
    }

    // MARK: - Phases and actors

    private mutating func phaseField(at index: Int, stage: Int) {
        let field = fields.fields[index]
        switch field.type {
        case "NAM0":
            phase.name = fields.read(at: index) { try $0.readZString() }
        case "NEXT":
            fields.markUsed(at: index)
            mode = .phase(stage: stage + 1)
        case "WNAM":
            phase.editorWidth = fields.read(at: index) { try $0.readUInt32() }
        case "HNAM":
            fields.markUsed(at: index)
            phase.startConditions = phaseRuns[0].conditions
            phase.completionConditions = phaseRuns[1].conditions
            phases.append(phase)
            mode = .top
        default:
            guard ConditionList.isConditionField(field.type) else { return }
            guard stage < 2 else {
                fields.markUsed(at: index)
                fields.note(.mismatch("SCEN phase condition after the second NEXT"))
                return
            }
            _ = fields.read(at: index) { _ in try phaseRuns[stage].decode(field: field) }
        }
    }

    private mutating func actorField(at index: Int) -> Bool {
        guard !actors.isEmpty else { return false }
        switch fields.fields[index].type {
        case "LNAM": actors[actors.count - 1].flags = fields.read(at: index) { try $0.readUInt32() }
        case "DNAM": actors[actors.count - 1].behaviorFlags = fields
            .read(at: index) { try $0.readUInt32() }
        default: return false
        }
        return true
    }

    // MARK: - Actions

    private mutating func actionField(at index: Int) {
        guard var current = action else { return }
        if fields.fields[index].type == "ANAM" {
            fields.markUsed(at: index)
            current.payload = payload(for: current.type)
            actions.append(current)
            action = nil
            mode = .top
            return
        }
        if !commonActionField(at: index, into: &current) {
            _ = payloadField(at: index, startPhaseSeen: current.startPhase != nil)
        }
        action = current
    }

    private mutating func commonActionField(
        at index: Int,
        into current: inout SceneAction
    ) -> Bool {
        switch fields.fields[index].type {
        case "NAM0": current.name = fields.read(at: index) { try $0.readZString() }
        case "ALID": current.aliasID = fields.read(at: index) { try $0.readInt32() }
        case "LNAM": current.unknownLNAM = fields
            .read(at: index) { try $0.read(count: $0.bytesRemaining) }
        case "INAM": current.index = fields.read(at: index) { try $0.readUInt32() }
        case "FNAM": current.flags = fields.read(at: index) { try $0.readUInt32() }
        case "ENAM": current.endPhase = fields.read(at: index) { try $0.readUInt32() }
        case "SNAM" where current.startPhase == nil:
            current.startPhase = fields.read(at: index) { try $0.readUInt32() }
        default: return false
        }
        return true
    }

    private mutating func payloadField(at index: Int, startPhaseSeen: Bool) -> Bool {
        switch fields.fields[index].type {
        case "DATA": dialogue.topic = fields.read(at: index) { try $0.readFormID() }?.nonNull
        case "HTID": dialogue.headtrackAliasID = fields.read(at: index) { try $0.readInt32() }
        case "DMAX": dialogue.loopingMax = fields.read(at: index) { try $0.readFloat32() }
        case "DMIN": dialogue.loopingMin = fields.read(at: index) { try $0.readFloat32() }
        case "DEMO": dialogue.emotionType = fields.read(at: index) { try $0.readUInt32() }
        case "DEVA": dialogue.emotionValue = fields.read(at: index) { try $0.readUInt32() }
        case "PNAM": packages += fields.read(at: index) { try $0.readFormID() }.map { [$0] } ?? []
        case "SNAM" where startPhaseSeen: timer = fields.read(at: index) { try $0.readFloat32() }
        default: return false
        }
        return true
    }

    private func payload(for type: UInt16) -> SceneActionPayload {
        switch type {
        case 0: .dialogue(dialogue)
        case 1: .package(packages)
        case 2: .timer(timer)
        default: .unknown
        }
    }
}

nonisolated extension SceneAction {
    init(type: UInt16, payload: SceneActionPayload) {
        self.type = type
        self.payload = payload
    }
}

nonisolated extension SceneActorBehavior {
    init(_ reader: inout BinaryReader) throws {
        death = try reader.readUInt32()
        combat = try reader.readUInt32()
        dialogue = try reader.readUInt32()
        observeCombat = try reader.readUInt32()
    }
}
