// The variable storage one behavior graph instance owns (issue #187).
//
// `hkbBehaviorGraphData` declares the variables positionally: index i has type
// `m_variableInfos[i]`, name `m_stringData.m_variableNames[i]`, and initial
// value in `m_variableInitialValues` — word list for bool, int, and real,
// quad list for vector and quaternion. This type is that storage, seeded from
// those declarations and mutable at runtime.
//
// External callers address variables by name (`bIsSprinting`, `Speed`), which
// is what item 14.5 will bind engine state to. Indices stay available because
// `hkbVariableBindingSet` addresses them positionally and never by name.
//
// Word storage keeps the raw i32 the packfile stores, including a real's float
// bit pattern, so a round trip through this store is byte-exact and an unknown
// declared type still reads and writes without loss.

import Foundation
import simd

/// One variable's value, in the shape the declared type asks for. Reading a
/// variable through the wrong accessor coerces rather than failing, because a
/// binding names a member whose Swift type is fixed while the authored variable
/// type is whatever the graph author chose.
nonisolated enum BehaviorVariableValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int32)
    case real(Float)
    case quad(SIMD4<Float>)

    /// The value as a float, which is what a bound float member wants.
    var realValue: Float {
        switch self {
        case let .bool(value): value ? 1 : 0
        case let .int(value): Float(value)
        case let .real(value): value
        case let .quad(value): value.x
        }
    }

    /// The value as an integer, which is what a bound index or enum member
    /// wants. A real truncates toward zero.
    var intValue: Int {
        switch self {
        case let .bool(value): value ? 1 : 0
        case let .int(value): Int(value)
        case let .real(value): value.isFinite ? Int(value) : 0
        case let .quad(value): value.x.isFinite ? Int(value.x) : 0
        }
    }

    /// The value as a bool. Havok treats any non-zero word as true.
    var boolValue: Bool {
        switch self {
        case let .bool(value): value
        case let .int(value): value != 0
        case let .real(value): value != 0
        case let .quad(value): value.x != 0
        }
    }
}

/// Every graph variable of one instance: its declaration and its current value.
/// Two instances built from the same `hkbBehaviorGraphData` start identical and
/// diverge only through the setters, which is what makes 14.7's second graph
/// instance independent of the first.
nonisolated struct BehaviorVariableStore: Equatable {
    /// Declared name per index; nil where the graph declares none.
    let names: [String?]
    /// Declared type per index; nil where the byte on disk names no known type.
    let types: [HKBVariableType?]

    /// Raw word slot per index, as `hkbVariableValueSet::m_wordVariableValues`
    /// stores it. A real variable's float lives here as its bit pattern.
    private var words: [Int32]
    /// Quad slot per index. Vector and quaternion variables index this list
    /// with the same index they use for `words`, which is how Havok addresses
    /// them: one variable index, two parallel arrays, the declared type picks.
    private var quads: [SIMD4<Float>]
    /// Name -> index, built once. First declaration wins, so a duplicated name
    /// in a modded graph resolves to the same index every run.
    private let indexByName: [String: Int]

    /// Builds the store from the graph's declarations. A missing or short
    /// initial-value set is not a fault: Havok omits trailing zeros, so any
    /// index the value set does not reach starts at zero.
    init(data: HKBBehaviorGraphData?) {
        let infos = data?.variableInfos ?? []
        let declaredNames = data?.stringData?.variableNames ?? []
        let count = max(infos.count, declaredNames.count)
        var names = [String?](repeating: nil, count: count)
        for (index, name) in declaredNames.enumerated() where index < count {
            names[index] = name
        }
        var types = [HKBVariableType?](repeating: nil, count: count)
        for (index, info) in infos.enumerated() where index < count {
            types[index] = info.type
        }
        self.names = names
        self.types = types

        let initial = data?.variableInitialValues
        var words = [Int32](repeating: 0, count: count)
        for (index, value) in (initial?.wordValues ?? []).enumerated() where index < count {
            words[index] = Int32(truncatingIfNeeded: value)
        }
        var quads = [SIMD4<Float>](repeating: SIMD4<Float>(), count: count)
        for (index, value) in (initial?.quadValues ?? []).enumerated() where index < count {
            quads[index] = value
        }
        self.words = words
        self.quads = quads

        var byName: [String: Int] = [:]
        for (index, name) in names.enumerated() {
            guard let name, byName[name] == nil else { continue }
            byName[name] = index
        }
        indexByName = byName
    }

    var count: Int {
        words.count
    }

    /// The declared index of `name`, or nil when the graph declares no such
    /// variable. Names are matched exactly; Havok's are case-sensitive.
    func index(of name: String) -> Int? {
        indexByName[name]
    }

    // MARK: - Reading

    /// The value at `index` in the shape its declared type asks for, or nil
    /// when the index is out of range. An index whose declared type is unknown
    /// reads as `.int`, which preserves the stored word.
    func value(at index: Int) -> BehaviorVariableValue? {
        guard words.indices.contains(index) else { return nil }
        switch types[index] {
        case .bool:
            return .bool(words[index] != 0)
        case .real:
            return .real(Float(bitPattern: UInt32(bitPattern: words[index])))
        case .vector3, .vector4, .quaternion:
            return .quad(quads[index])
        case .int8, .int16, .int32, .pointer, .invalid, .none:
            return .int(words[index])
        }
    }

    func value(of name: String) -> BehaviorVariableValue? {
        index(of: name).flatMap { value(at: $0) }
    }

    // MARK: - Writing

    /// Stores `value` at `index`, coerced to the declared type. Out of range is
    /// a no-op rather than a trap: a caller naming a variable a modded graph
    /// dropped must not crash the engine.
    mutating func setValue(_ value: BehaviorVariableValue, at index: Int) {
        guard words.indices.contains(index) else { return }
        switch types[index] {
        case .bool:
            words[index] = value.boolValue ? 1 : 0
        case .real:
            words[index] = Int32(bitPattern: value.realValue.bitPattern)
        case .vector3, .vector4, .quaternion:
            if case let .quad(quad) = value {
                quads[index] = quad
            } else {
                quads[index] = SIMD4(value.realValue, 0, 0, 0)
            }
        case .int8, .int16, .int32, .pointer, .invalid, .none:
            words[index] = Int32(truncatingIfNeeded: value.intValue)
        }
    }

    /// Stores `value` under `name`. Returns false when the graph declares no
    /// such variable, so a caller wiring engine state can report the miss.
    @discardableResult
    mutating func setValue(_ value: BehaviorVariableValue, of name: String) -> Bool {
        guard let index = index(of: name) else { return false }
        setValue(value, at: index)
        return true
    }
}
