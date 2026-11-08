// The output half of `hkbVariableBindingSet`. A modifier member such as
// `BSIsActiveModifier.bIsActive0` or `BSInterpValueModifier.result` is computed by
// the node and copied back to the variable it is bound to, after the node runs.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// Copies each computed member in `outputs` back to every graph variable a
    /// binding of `node` ties it to. Keys are member paths without the `m_` prefix.
    public func writeOutputs(
        _ outputs: [String: BehaviorVariableValue],
        of node: BehaviorCompiledNode
    ) {
        guard let compiled = node.bindings, !outputs.isEmpty else { return }
        for (index, binding) in compiled.bindings.enumerated() {
            guard
                binding.bindingType == 0,
                let path = compiled.paths[index],
                let value = outputs[path]
            else {
                continue
            }
            writeVariable(value, at: binding.variableIndex, bit: binding.bitIndex)
        }
    }

    /// The variable indexes `node` writes `path` to.
    public func outputIndexes(of node: BehaviorCompiledNode, path: String) -> [Int] {
        guard let compiled = node.bindings else { return [] }
        return compiled.bindings.indices.compactMap { index in
            compiled.paths[index] == path && compiled.bindings[index].bindingType == 0
                ? compiled.bindings[index].variableIndex : nil
        }
    }
}
