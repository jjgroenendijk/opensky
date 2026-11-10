// `nif <key> --controllers`: the controllers that move nodes on their own clock, as the
// engine reads them, and the bone LOD levels ([NIF controllers](docs/formats/nif-controllers.md)).

import Foundation
import OpenSkyFormatsMesh

enum NIFControllerReport {
    static func print(file: NIFFile) {
        printShaderControllers(file: file)
        let animation: NIFNodeAnimation
        do {
            animation = try NIFNodeAnimationDecoder.animation(of: file)
        } catch {
            printError("[WARNING] node controllers failed: \(String(describing: error))")
            return
        }
        Swift.print("node controllers: \(animation.controllers.count)")
        for controller in animation.controllers {
            let timing = controller.timing
            Swift.print(
                "controller \(controller.typeName) on \(name(controller.node, animation)) "
                    + (controller.isActive ? "active" : "inactive")
                    + " \(timing.cycle) \(format(timing.startTime))-\(format(timing.stopTime))"
                    + " x\(format(timing.frequency)): \(describe(controller.motion, animation))"
            )
        }
        guard let lod = animation.boneLOD else { return }
        for bone in lod.bones {
            Swift.print("bone LOD \(bone.name ?? "-") at \(format(bone.distance))"
                + (bone.node == nil ? " (no such node)" : ""))
        }
        for (level, group) in lod.levels.enumerated() {
            Swift.print("bone LOD level \(level): "
                + group.map { name($0, animation) }.joined(separator: ", "))
        }
    }

    /// Shader property controllers with the nif.xml name of the variable each drives.
    private static func printShaderControllers(file: NIFFile) {
        let entries: [NIFShaderControllerEntry]
        do {
            entries = try NIFShaderAnimation.controllers(in: file)
        } catch {
            printError("[WARNING] shader controllers failed: \(String(describing: error))")
            return
        }
        Swift.print("shader controllers: \(entries.count)")
        for entry in entries {
            let timing = entry.timing
            let state = entry.isManagerControlled ? "sequence"
                : entry.isActive ? "active" : "inactive"
            let variable = entry.variableName ?? "variable \(entry.variable)"
            Swift.print(
                "controller \(entry.kind.rawValue) on block \(entry.shaderBlock) \(state)"
                    + " \(timing.cycle) \(format(timing.startTime))-\(format(timing.stopTime))"
                    + " x\(format(timing.frequency)): \(variable)"
                    + ", \(entry.keyCount) keys" + (entry.target == nil ? ", not drawn" : "")
            )
        }
    }

    private static func describe(
        _ motion: NIFNodeAnimation.Motion, _ animation: NIFNodeAnimation
    ) -> String {
        switch motion {
        case let .keys(channel):
            let keys = channel.keys
            return "keys t \(keys?.translations.count ?? 0) r \(keys?.rotations.count ?? 0)"
                + " s \(keys?.scales.count ?? 0)"
        case let .path(path):
            let source = path.interpolator
            return "path \(path.points.count) points, flags \(source.flags), follow axis "
                + "\(source.followAxis), bank \(source.bankDirection) max "
                + "\(format(source.maximumBankAngle)), smoothing \(format(source.smoothing))"
        case let .lookAt(lookAt):
            return "look at \(lookAt.target.map { name($0, animation) } ?? "-") axis "
                + "\(NIFSequenceReport.format(lookAt.axis)), roll keys \(lookAt.roll.count)"
        case let .lag(lag):
            return "lag velocity \(format(lag.linearVelocity)) rotation "
                + "\(format(lag.linearRotation)) max distance \(format(lag.maximumDistance))"
        }
    }

    private static func name(_ node: Int, _ animation: NIFNodeAnimation) -> String {
        animation.nodes[node].name ?? "node \(node)"
    }

    private static func format(_ value: Float) -> String {
        NIFSequenceReport.format(value)
    }
}
