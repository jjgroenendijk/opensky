// The player's Activate perk choices on a use-key press: run-now choices run, one
// offered choice runs alone, and several open a menu beside the target's own action.
// `PerkActivationPlan` holds the rules. See docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

/// What the activation coordinator needs from the app.
@MainActor
public protocol PerkActivationWorld: AnyObject {
    func referenceKey(of target: InteractionTarget) -> ReferenceKey?
    /// The player's passing Activate choices, with `target` bound as the target.
    func activateChoices(on target: ReferenceKey) -> [PerkEntryPointChoice]
    func text(_ value: LString) -> String?
    /// Queues the choice's perk fragment as `Fragment_N(akTargetRef, akActor)`.
    func runPerkFragment(
        _ choice: PerkActivateChoice, actor: ReferenceKey, target: ReferenceKey
    ) -> Bool
    func applyActivateSpell(
        _ spell: ResolvedSpell, caster: ReferenceKey, on target: ReferenceKey
    ) -> Bool
    /// The target's own action, without asking the perks again.
    func performDefaultActivation(_ target: InteractionTarget)
    var crosshairTarget: InteractionTarget? { get }
}

/// What running one choice did.
nonisolated public struct PerkChoiceRun: Equatable, Sendable {
    public let label: String
    public let ranFragment: Bool
    public let castSpell: Bool

    public var text: String {
        let parts = [ranFragment ? "fragment" : nil, castSpell ? "spell" : nil].compactMap(\.self)
        return "\(label): " + (parts.isEmpty ? "nothing ran" : parts.joined(separator: " and "))
    }
}

public final class PerkActivationCoordinator {
    public weak let world: (any PerkActivationWorld)?
    private let messages: MessageCoordinator
    public private(set) var lastRun: PerkChoiceRun?

    public static let actor = ReferenceKey.player

    public init(messages: MessageCoordinator, world: (any PerkActivationWorld)? = nil) {
        self.messages = messages
        self.world = world
    }

    /// True when the perks took the press over, so the target's own action does not
    /// run now. It may still run later, from the menu.
    @discardableResult
    public func activate(_ target: InteractionTarget) -> Bool {
        guard let key = world?.referenceKey(of: target) else { return false }
        let plan = plan(on: key)
        guard !plan.isEmpty else { return false }
        for choice in plan.immediate {
            run(choice, on: key)
        }
        switch plan.step {
        case .defaultAction:
            return false
        case .nothing:
            return true
        case let .single(choice):
            run(choice, on: key)
            return true
        case .menu:
            presentMenu(plan, target: target, key: key)
            return true
        }
    }

    /// The prompt label when one choice replaces the target's own action.
    public func promptLabel(on key: ReferenceKey) -> String? {
        guard case let .single(choice) = plan(on: key).step else { return nil }
        return label(of: choice)
    }

    @discardableResult
    public func run(_ choice: PerkEntryPointChoice, on target: ReferenceKey) -> PerkChoiceRun {
        let ranFragment = choice.activation.map {
            world?.runPerkFragment($0, actor: Self.actor, target: target) ?? false
        } ?? false
        let castSpell = choice.spell.map {
            world?.applyActivateSpell($0, caster: Self.actor, on: target) ?? false
        } ?? false
        let run = PerkChoiceRun(
            label: label(of: choice),
            ranFragment: ranFragment,
            castSpell: castSpell
        )
        lastRun = run
        return run
    }

    func plan(on key: ReferenceKey) -> PerkActivationPlan {
        PerkActivationPlan(choices: world?.activateChoices(on: key) ?? [])
    }

    func label(of choice: PerkEntryPointChoice) -> String {
        choice.activation?.label.flatMap { world?.text($0) } ?? Self.unlabelled
    }

    static let unlabelled = "Perk choice"

    private func presentMenu(
        _ plan: PerkActivationPlan,
        target: InteractionTarget,
        key: ReferenceKey
    ) {
        let offered = plan.offered
        var buttons = offered.map(label(of:))
        if plan.keepsDefault {
            let verb = target.interaction.actionLabel
            buttons.append(verb.isEmpty ? target.interaction.action.defaultLabel : verb)
        }
        messages.presentChoices(
            title: nil, text: target.interaction.name, buttons: buttons
        ) { [weak self] index in
            guard let self else { return }
            if offered.indices.contains(index) {
                run(offered[index], on: key)
            } else if plan.keepsDefault, index == offered.count {
                world?.performDefaultActivation(target)
            }
        }
    }
}
