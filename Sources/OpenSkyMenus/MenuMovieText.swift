// Small writes into a menu movie: a text field by path, and a `Components.Meter`
// object that a clip holds as a property rather than as a child.

import Foundation
import OpenSkyFormatsSWF

nonisolated enum MenuMovieText {
    static func set(_ text: String, atPath path: String, runtime: SWFMovieRuntime) {
        guard let node = runtime.node(atPath: path, from: runtime.root) else { return }
        runtime.setText(text, of: node)
    }

    /// Calls `meter.<method>(percent)` on the meter object the clip at `path` holds.
    static func callMeter(
        _ method: String, meter: String, ofPath path: String, percent: Double,
        runtime: SWFMovieRuntime
    ) {
        guard
            let owner = runtime.node(atPath: path, from: runtime.root),
            let object = owner.object.lookup(meter)?.property.value.objectValue,
            let function = object.lookup(method)?.property.value.functionValue
        else { return }
        runtime.markDirty()
        runtime.runtime.invoke(
            .object(function), thisValue: .object(object), arguments: [.number(percent)]
        )
    }

    /// Writes `member` on the object at `path` through its setter, as a CLIK component's
    /// `text` property needs, or as a plain property when it has none.
    static func assign(
        _ value: AS2Value, member: String, atPath path: String, runtime: SWFMovieRuntime
    ) {
        guard let node = runtime.node(atPath: path, from: runtime.root) else { return }
        runtime.markDirty()
        if let setter = node.object.lookup(member)?.property.setter {
            runtime.runtime.invoke(
                .object(setter), thisValue: .object(node.object), arguments: [value]
            )
        } else {
            node.object.define(value, for: member)
        }
    }
}
