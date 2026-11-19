// What the idle runtime needs from a running sandbox: the area it takes markers in.

public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

extension PackageCoordinator {
    /// The cylinder round the sandbox's place, with `fSandboxCylinderBottom` and
    /// `fSandboxCylinderTop` as its height. Nil when the actor runs no sandbox with a radius.
    public func sandboxArea(of actor: ReferenceKey) -> IdleSearchArea? {
        guard let machine = executions[actor]?.sandboxMachine, machine.radius > 0 else {
            return nil
        }
        return machine.idleArea(defaults: settings.sandbox)
    }

    /// A sandbox with Allow Conversation sets the running package's random conversation
    /// flag, 0x02 (docs/engine/random-conversations.md#package-interrupt-flags).
    public func allowsSandboxConversation(_ actor: ReferenceKey) -> Bool {
        executions[actor]?.sandboxMachine?.setup.sandbox?.allowsConversation ?? false
    }
}
