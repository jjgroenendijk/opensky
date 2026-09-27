// The progression half of the world-provider fake (issue #500), in its own file
// so `FakeWorldProviders` stays inside the type-length cap — the same split
// `FakeWorldProvidersCombat.swift` made.
//
// Every answer is a plain stored value and every action is recorded rather than
// performed, which is what lets a panel test drive the whole `World >
// Progression` destination with no renderer, no window and no game data.

@testable import opensky

/// The progression half of the fake's stored state.
struct FakeProgressionState {
    var snapshot = ProgressionControlSnapshot.unavailable
    /// How many times the panel has asked for the snapshot, so a gate can assert
    /// that one tick builds it once for all three sections (issue #556).
    var snapshotReads = 0
    /// Every skill use the panel granted, in order, so a gate can assert that a
    /// button sent exactly what the field held.
    var uses: [Float] = []
    var incrementCount = 0
    /// Every character-experience award the panel asked for, newest last.
    var awards: [Float] = []
    /// Every attribute pick the panel spent, in order.
    var picks: [ActorValueKind] = []
    /// Every perk-point change the panel asked for, in order.
    var perkPointDeltas: [Int] = []
    var spendCount = 0
    var grantCount = 0
    var revokeCount = 0
}

/// The conformance itself is declared by `WorldControlProviders` on the class,
/// so this is a plain extension: restating it here would be a redundant
/// conformance.
extension FakeWorldProviders {
    var progressionControlSnapshot: ProgressionControlSnapshot {
        progression.snapshotReads += 1
        return progression.snapshot
    }

    var progressionSkillSelection: Int32 {
        get { progression.snapshot.selectedSkill }
        set { progression.snapshot = progression.snapshot.selecting(skill: newValue) }
    }

    var progressionNodeSelection: UInt32 {
        get { progression.snapshot.selectedNode }
        set { progression.snapshot = progression.snapshot.selecting(node: newValue) }
    }

    @discardableResult
    func advanceSelectedSkill(byUse amount: Float) -> String {
        progression.uses.append(amount)
        return record("Granted \(amount) use.")
    }

    @discardableResult
    func incrementSelectedSkill() -> String {
        progression.incrementCount += 1
        return record("Granted a skill point.")
    }

    @discardableResult
    func awardCharacterExperience(_ amount: Float) -> String {
        progression.awards.append(amount)
        return record("Awarded \(amount) character XP.")
    }

    @discardableResult
    func chooseAttributePick(_ kind: ActorValueKind) -> String {
        progression.picks.append(kind)
        return record("Chose \(kind.rawValue).")
    }

    @discardableResult
    func changePerkPoints(by delta: Int) -> String {
        progression.perkPointDeltas.append(delta)
        return record("Changed perk points by \(delta).")
    }

    @discardableResult
    func spendPointOnSelectedPerk() -> String {
        progression.spendCount += 1
        return record("Spent a perk point.")
    }

    @discardableResult
    func grantSelectedPerk() -> String {
        progression.grantCount += 1
        return record("Granted the selected perk.")
    }

    @discardableResult
    func revokeSelectedPerk() -> String {
        progression.revokeCount += 1
        return record("Removed the selected perk.")
    }

    /// Puts an action's outcome where the readout reads it, so a panel test
    /// sees the same line a session would.
    private func record(_ text: String) -> String {
        progression.snapshot = progression.snapshot.reporting(text)
        return text
    }
}

extension ProgressionControlSnapshot {
    /// The same reading with one field replaced. The snapshot is a `let`-only
    /// value by design, so a fake that has to move a selection rebuilds it
    /// rather than the type growing setters no session would use.
    func selecting(skill index: Int32) -> ProgressionControlSnapshot {
        copy(selectedSkill: index)
    }

    func selecting(node: UInt32) -> ProgressionControlSnapshot {
        copy(selectedNode: node)
    }

    func reporting(_ text: String) -> ProgressionControlSnapshot {
        copy(lastActionText: text)
    }

    private func copy(
        selectedSkill: Int32? = nil,
        selectedNode: UInt32? = nil,
        lastActionText: String? = nil
    ) -> ProgressionControlSnapshot {
        ProgressionControlSnapshot(
            isAvailable: isAvailable,
            level: level,
            experience: experience,
            experienceForNextLevel: experienceForNextLevel,
            perkPoints: perkPoints,
            pendingAttributePicks: pendingAttributePicks,
            attributePicks: attributePicks,
            skillIncreases: skillIncreases,
            ownedPerkCount: ownedPerkCount,
            skills: skills,
            perkTreeCache: perkTreeCache,
            selectedSkill: selectedSkill ?? self.selectedSkill,
            treeNodes: treeNodes,
            selectedNode: selectedNode ?? self.selectedNode,
            perk: perk,
            lastActionText: lastActionText ?? self.lastActionText
        )
    }
}
