// What the last AI navigation control did, as a value. Only `text` builds the line.

import OpenSkyFormatsESM
import OpenSkyNavigation

nonisolated public enum AINavigationActionOutcome: Equatable, Sendable {
    case idle
    case selected(String)
    /// `verb` is the refused control: "set hostility", "move", "stop", "reevaluate".
    case noActor(verb: String)
    case regardSet(actor: String, hostile: Bool)
    case crosshairEmpty(verb: String)
    case notAnActor(FormID)
    case moved(NPCMoveCommandResult, actor: String)
    case stopped(actor: String, hadMover: Bool)
    case noPackageStack(actor: String)
    case reevaluated(actor: String, PackageActorReadout)
    case unknownPackage(String)
    /// Nil `package` removed the script package.
    case scriptPackage(actor: String, package: String?)

    public var text: String {
        switch self {
        case .idle: "Select an actor, then move it, or watch its schedule."
        case let .selected(name): "Selected \(name)."
        case .noActor(verb: "set hostility"): "Cannot set hostility: no resident actor."
        case let .noActor(verb): "Cannot \(verb): no resident actor to act on."
        case let .regardSet(actor, hostile): "\(actor) is now \(hostile ? "hostile" : "neutral")."
        case let .crosshairEmpty(verb): "Cannot \(verb): the crosshair is not on anything."
        case let .notAnActor(reference):
            "Cannot select: \(reference) under the crosshair is not an actor."
        case let .moved(result, actor): AINavigationReadout.moveResultText(result, actor: actor)
        case let .stopped(actor, hadMover):
            hadMover ? "Stopped \(actor) where it stands." : "\(actor) had no mover to stop."
        case let .noPackageStack(actor): "\(actor) has no package stack registered."
        case let .reevaluated(actor, readout):
            "Reevaluated \(actor): " + AIPackageReadout.selectionText(for: readout)
        case let .unknownPackage(name): "No package is named \(name)."
        case let .scriptPackage(actor, package?): "\(actor) runs script package \(package)."
        case let .scriptPackage(actor, nil): "\(actor) has no script package."
        }
    }
}
