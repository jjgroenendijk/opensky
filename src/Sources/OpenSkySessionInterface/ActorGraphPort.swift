public import OpenSkyBehavior
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface

/// What the world adapters use of `ActorGraphCoordinator`.
public protocol ActorGraphPort: AnyObject {
    associatedtype ActorGraphLoan: ActorGraphLoanPort
    var footIk: Bool { get set }
    func instance(of actor: ReferenceKey) -> BehaviorGraphInstance?
    func movementStateName(of actor: ReferenceKey) -> String?
    func pose(of actor: ReferenceKey) -> PlayerPoseBuffer?
    @discardableResult func raise(_ event: String, on actor: ReferenceKey) -> Bool
    func readout(for actor: ReferenceKey) -> ActorGraphReadout?
    func setMotion(_ motion: ActorGraphMotion, for actor: ReferenceKey)
    @discardableResult func setVariable(
        _ value: BehaviorVariableValue,
        named name: String,
        on actor: ReferenceKey
    ) -> Bool
    func giveBack(_ actor: ReferenceKey)
    func lend(_ actor: ReferenceKey) -> ActorGraphLoan?
    func report(_ names: [String], from actor: ReferenceKey)

    func awaitEvent(_ event: String, on actor: ReferenceKey) -> UInt64?
    func load(settings store: PlayerSettingsStore)
    func tick(deltaTime: Float)
    func variable(named name: String, on actor: ReferenceKey) -> BehaviorVariableValue?
    func variableResolution(player: BehaviorVariableStore?) -> GraphVariableResolution
}
