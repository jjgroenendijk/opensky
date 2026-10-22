// The use key with Activate perk choices: run-now choices run, a replacing choice
// hides the target's own action, and several choices open a menu that also offers it.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyProgressionInterface
import OpenSkyWorldInterface
import Testing

@MainActor
final class FakePerkActivationWorld: PerkActivationWorld {
    var choices: [PerkEntryPointChoice] = []
    var fragments: [FragmentCall] = []
    var spells: [SpellCall] = []
    var defaults: [InteractionTarget] = []
    var crosshairTarget: InteractionTarget?

    func referenceKey(of target: InteractionTarget) -> ReferenceKey? {
        .plugin(name: "skyrim.esm", objectID: target.interaction.reference.rawValue)
    }

    func activateChoices(on _: ReferenceKey) -> [PerkEntryPointChoice] {
        choices
    }

    func text(_ value: LString) -> String? {
        guard case let .inline(text) = value else { return nil }
        return text
    }

    func runPerkFragment(
        _ choice: PerkActivateChoice, actor: ReferenceKey, target: ReferenceKey
    ) -> Bool {
        fragments.append(FragmentCall(index: choice.fragmentIndex, actor: actor, target: target))
        return choice.fragment != nil
    }

    func applyActivateSpell(
        _ spell: ResolvedSpell, caster _: ReferenceKey, on target: ReferenceKey
    ) -> Bool {
        spells.append(SpellCall(spell: ReferenceKey(resolved: spell.id), target: target))
        return true
    }

    func performDefaultActivation(_ target: InteractionTarget) {
        defaults.append(target)
    }
}

struct FragmentCall: Equatable {
    let index: UInt16?
    let actor: ReferenceKey
    let target: ReferenceKey
}

struct SpellCall: Equatable {
    let spell: ReferenceKey
    let target: ReferenceKey
}

@MainActor
struct PerkActivationHarness {
    let coordinator: PerkActivationCoordinator
    let world = FakePerkActivationWorld()
    let messages: MessageCoordinator
    let menuMode = MenuModeController()

    init(_ choices: [PerkEntryPointChoice]) {
        world.choices = choices
        messages = MessageCoordinator(menuMode: menuMode, world: MessageCoordinatorTests.world())
        coordinator = PerkActivationCoordinator(messages: messages, world: world)
    }
}

@MainActor
struct PerkActivationCoordinatorTests {
    private let target = HUDCoreTests.target(reference: 0x14)
    private var targetKey: ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: 0x14)
    }

    private func choices(of editorID: String) throws -> [PerkEntryPointChoice] {
        let perk = try #require(PerkActivateFixture.store().perk(editorID: editorID))
        return perk.effects.compactMap { PerkEntryPointChoice(effect: $0, perk: perk) }
    }

    @Test func aChoiceCarriesItsLabelFlagsAndFragment() throws {
        let feed = try choices(of: "VampireFeed")
        let activation = try #require(feed.first?.activation)

        #expect(feed.count == 2)
        #expect(activation.label == .inline("Feed"))
        #expect(!activation.runsImmediately)
        #expect(!activation.replacesDefault)
        #expect(activation.fragment?.functionName == "Fragment_15")
        #expect(activation.fragment?.scriptName == PerkActivateFixture.feedScript)
        #expect(activation.perkKey == .plugin(
            name: PerkActivateFixture.pluginName.lowercased(), objectID: PerkActivateFixture.feed
        ))
    }

    @Test func noChoiceLeavesThePressToTheTarget() {
        let harness = PerkActivationHarness([])
        let (coordinator, world, menuMode) = (harness.coordinator, harness.world, harness.menuMode)

        #expect(!coordinator.activate(target))
        #expect(world.fragments.isEmpty)
        #expect(menuMode.topMenu == nil)
    }

    @Test func twoChoicesOpenAMenuThatKeepsTheTargetsAction() throws {
        let harness = try PerkActivationHarness(choices(of: "VampireFeed"))
        let (coordinator, world, messages) = (harness.coordinator, harness.world, harness.messages)
        let menuMode = harness.menuMode

        #expect(coordinator.activate(target))
        #expect(menuMode.topMenu == MessageCoordinator.identifier)
        #expect(messages.boxes.current?.buttons.map(\.text) == ["Feed", "Feed in bed", "Open"])
        #expect(coordinator.promptLabel(on: targetKey) == nil)

        messages.route(.button(.accept))
        #expect(world.fragments.map(\.index) == [1])
        #expect(world.fragments.first?.actor == .player)
        #expect(world.fragments.first?.target == targetKey)
        #expect(coordinator.lastRun?.text == "Feed: fragment")
        #expect(world.defaults.isEmpty)
    }

    @Test func theMenuCanStillRunTheTargetsAction() throws {
        let harness = try PerkActivationHarness(choices(of: "VampireFeed"))
        let (coordinator, world, messages) = (harness.coordinator, harness.world, harness.messages)

        coordinator.activate(target)
        messages.choose(row: 2)
        #expect(world.fragments.isEmpty)
        #expect(world.defaults == [target])
    }

    @Test func aRunNowChoiceThatReplacesTheActionRunsAloneAndCastsItsSpell() throws {
        let harness = try PerkActivationHarness(choices(of: "PlayerWerewolfFeed"))
        let (coordinator, world, menuMode) = (harness.coordinator, harness.world, harness.menuMode)

        #expect(coordinator.activate(target))
        #expect(menuMode.topMenu == nil)
        #expect(world.fragments.map(\.index) == [0])
        #expect(world.spells.map(\.spell) == [.plugin(
            name: PerkActivateFixture.pluginName.lowercased(),
            objectID: PerkActivateFixture.beastFeedSpell
        )])
        #expect(world.spells.map(\.target) == [targetKey])
        #expect(world.defaults.isEmpty)
    }

    @Test func oneReplacingChoiceRunsWithoutAMenuAndLabelsThePrompt() {
        let replacing = PerkEntryPointChoice(activation: PerkActivateChoice(
            label: .inline("Harvest blood"), replacesDefault: true, fragmentIndex: 0
        ))
        let harness = PerkActivationHarness([replacing])
        let (coordinator, world, menuMode) = (harness.coordinator, harness.world, harness.menuMode)

        #expect(coordinator.promptLabel(on: targetKey) == "Harvest blood")
        #expect(coordinator.activate(target))
        #expect(menuMode.topMenu == nil)
        #expect(world.fragments.map(\.index) == [0])
    }

    @Test func aRunNowChoiceThatKeepsTheActionLetsThePressThrough() {
        let runNow = PerkEntryPointChoice(activation: PerkActivateChoice(
            label: nil, runsImmediately: true, fragmentIndex: 2
        ))
        let harness = PerkActivationHarness([runNow])
        let (coordinator, world) = (harness.coordinator, harness.world)

        #expect(!coordinator.activate(target))
        #expect(world.fragments.map(\.index) == [2])
    }

    @Test func theSidebarListsAndRunsTheCrosshairChoices() throws {
        let harness = try PerkActivationHarness(choices(of: "VampireFeed"))
        let (coordinator, world) = (harness.coordinator, harness.world)
        world.crosshairTarget = target

        let snapshot = coordinator.perkActivationSnapshot
        #expect(snapshot.target == "Test Door")
        #expect(snapshot.rows.map(\.title) == ["Feed", "Feed in bed"])
        #expect(coordinator.runPerkChoice(at: 1))
        #expect(world.fragments.map(\.index) == [0])
        #expect(!coordinator.runPerkChoice(at: 5))
        #expect(coordinator.perkActivationSnapshot.readout
            .contains("Last run: Feed in bed: fragment"))
    }
}
