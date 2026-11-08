/// What the world adapters use of `ShoutMachine`.
public protocol ShoutMachinePort {
    var cooldown: Float { get }

    var wantsVoice: Bool { get }
}
