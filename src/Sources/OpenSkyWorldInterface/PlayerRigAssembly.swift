import OpenSkyFormatsAnimation
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// One rig to assemble. A result whose `generation` is not the newest is dropped.
nonisolated public struct PlayerRigRequest: Equatable, Sendable {
    public let generation: Int
    public let firstPerson: Bool
    public let equipped: [FormID]?
    public let appearance: PlayerAppearanceOverride?
    /// The texture set `Actor.SetEyeTexture` gave the player's eyes.
    public let eyeTextureSet: FormID?

    public init(
        generation: Int, firstPerson: Bool, equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?, eyeTextureSet: FormID? = nil
    ) {
        self.generation = generation
        self.firstPerson = firstPerson
        self.equipped = equipped
        self.appearance = appearance
        self.eyeTextureSet = eyeTextureSet
    }
}

nonisolated public struct PlayerRigLoadResult<Asset: Sendable, FaceMorph: Sendable>: Sendable {
    public let request: PlayerRigRequest
    public let result: Result<PlayerRigAssembly<Asset, FaceMorph>, PlayerBodyError>

    public init(
        request: PlayerRigRequest,
        result: Result<PlayerRigAssembly<Asset, FaceMorph>, PlayerBodyError>
    ) {
        self.request = request
        self.result = result
    }
}

/// The meshes of one rig, before they are bound to a skeleton and a pose.
nonisolated public struct PlayerRigAssembly<Asset: Sendable, FaceMorph: Sendable>: Sendable {
    public let assembly: ActorAssembly<Asset>
    /// Race, chargen, and expression morphs on the head parts; empty for the arms and a
    /// baked head.
    public let faceMorphs: [ObjectIdentifier: FaceMorph]

    public init(
        assembly: ActorAssembly<Asset>,
        faceMorphs: [ObjectIdentifier: FaceMorph] = [:]
    ) {
        self.assembly = assembly
        self.faceMorphs = faceMorphs
    }
}
