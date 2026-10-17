// Which script instances serve which running magic effects. Pure bookkeeping for the
// `ActiveMagicEffect` scripts (<https://ck.uesp.net/wiki/ActiveMagicEffect_Script>).
// See docs/engine/papyrus-magic-effects.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// One running magic effect: the actor it acts on and its per-actor application number.
nonisolated public struct PapyrusActiveEffectID: Hashable, Comparable, Sendable {
    public let target: ReferenceKey
    public let sequence: UInt64

    public init(target: ReferenceKey, sequence: UInt64) {
        self.target = target
        self.sequence = sequence
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.target != right.target ? left.target < right.target : left.sequence < right.sequence
    }
}

/// One running magic effect that carries scripts.
nonisolated public struct PapyrusActiveEffectRun: Equatable, Sendable {
    public let id: PapyrusActiveEffectID
    /// The `MGEF` record.
    public let effect: ReferenceKey
    public let caster: ReferenceKey?

    public init(id: PapyrusActiveEffectID, effect: ReferenceKey, caster: ReferenceKey?) {
        self.id = id
        self.effect = effect
        self.caster = caster
    }
}

/// The running effects and the instances that serve them. An instance is keyed by the
/// target and the script name, so two runs of one effect on one actor share it.
nonisolated public struct PapyrusEffectScripts: Equatable, Sendable {
    public private(set) var runs: [PapyrusActiveEffectID: PapyrusActiveEffectRun] = [:]
    /// The runs each instance serves, oldest first.
    public private(set) var runsByInstance: [PapyrusInstanceKey: [PapyrusActiveEffectID]] = [:]
    /// Instances whose last run ended. Each retires once its `OnEffectFinish` has run.
    public private(set) var finishing: Set<PapyrusInstanceKey> = []

    public init() {}

    public var instanceKeys: Set<PapyrusInstanceKey> {
        finishing.union(runsByInstance.keys)
    }

    public func contains(instance: PapyrusInstanceKey) -> Bool {
        runsByInstance[instance] != nil || finishing.contains(instance)
    }

    public mutating func begin(_ run: PapyrusActiveEffectRun) {
        runs[run.id] = run
    }

    /// Records that `instance` serves the run `id`. False when the run already ended.
    @discardableResult
    public mutating func attach(
        _ instance: PapyrusInstanceKey,
        to id: PapyrusActiveEffectID
    ) -> Bool {
        guard runs[id] != nil else { return false }
        finishing.remove(instance)
        if runsByInstance[instance]?.contains(id) != true {
            runsByInstance[instance, default: []].append(id)
        }
        return true
    }

    /// Ends the run `id`. Returns the instances that served it, and which of them now
    /// serve no run at all and so start finishing.
    public mutating func end(
        _ id: PapyrusActiveEffectID
    ) -> (served: [PapyrusInstanceKey], idle: [PapyrusInstanceKey]) {
        runs[id] = nil
        var served: [PapyrusInstanceKey] = []
        var idle: [PapyrusInstanceKey] = []
        for (instance, ids) in runsByInstance where ids.contains(id) {
            served.append(instance)
            let left = ids.filter { $0 != id }
            runsByInstance[instance] = left.isEmpty ? nil : left
            if left.isEmpty {
                idle.append(instance)
                finishing.insert(instance)
            }
        }
        return (served.sorted(), idle.sorted())
    }

    /// The oldest run `instance` serves, which its natives answer for.
    public func run(servedBy instance: PapyrusInstanceKey) -> PapyrusActiveEffectRun? {
        runsByInstance[instance]?.first.flatMap { runs[$0] }
    }

    /// Drops a retired instance. True when it served a magic effect.
    @discardableResult
    public mutating func forget(instance: PapyrusInstanceKey) -> Bool {
        let known = contains(instance: instance)
        runsByInstance[instance] = nil
        finishing.remove(instance)
        return known
    }
}
