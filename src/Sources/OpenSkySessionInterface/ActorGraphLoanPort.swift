public import OpenSkyBehavior
public import OpenSkyWorldInterface

/// What the world adapters use of `ActorGraphLoan`.
public protocol ActorGraphLoanPort {
    var instance: BehaviorGraphInstance { get }
    var pose: PlayerPoseBuffer { get }
}
