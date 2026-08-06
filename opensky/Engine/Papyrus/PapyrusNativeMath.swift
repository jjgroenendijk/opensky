// Every native declared by the vanilla Math script.

import Darwin
import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installMath(into registry: inout PapyrusNativeRegistry) {
        installMathRounding(into: &registry)
        installMathArithmetic(into: &registry)
        installMathTrigonometry(into: &registry)
    }

    private static func installMathRounding(into registry: inout PapyrusNativeRegistry) {
        registerUnaryFloat("Abs", into: &registry) { Swift.abs($0) }
        registerRoundedInteger("Floor", into: &registry) { Darwin.floor($0) }
        registerRoundedInteger("Ceiling", into: &registry) { Darwin.ceil($0) }
    }

    private static func installMathArithmetic(into registry: inout PapyrusNativeRegistry) {
        registerUnaryFloat("Sqrt", into: &registry) { Darwin.sqrt($0) }
        registry.register(PapyrusNativeFunction(
            scriptName: "Math",
            functionName: "Pow"
        ) { call, _ in
            guard
                let base = float(call, at: 0),
                let exponent = float(call, at: 1)
            else {
                return failure(call, "Pow needs two floats")
            }
            return .returned(.float(Darwin.pow(base, exponent)))
        })
        let degreesPerRadian = Float(180 / Double.pi)
        registerUnaryFloat("DegreesToRadians", into: &registry) {
            $0 / degreesPerRadian
        }
        registerUnaryFloat("RadiansToDegrees", into: &registry) {
            $0 * degreesPerRadian
        }
    }

    private static func installMathTrigonometry(
        into registry: inout PapyrusNativeRegistry
    ) {
        registerUnaryFloat("Sin", into: &registry) { Darwin.sin($0) }
        registerUnaryFloat("Cos", into: &registry) { Darwin.cos($0) }
        registerUnaryFloat("Tan", into: &registry) { Darwin.tan($0) }
        registerUnaryFloat("Asin", into: &registry) { Darwin.asin($0) }
        registerUnaryFloat("Acos", into: &registry) { Darwin.acos($0) }
        registerUnaryFloat("Atan", into: &registry) { Darwin.atan($0) }
    }

    private static func registerUnaryFloat(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @Sendable (Float) -> Float
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Math",
            functionName: functionName
        ) { call, _ in
            guard let value = float(call, at: 0) else {
                return failure(call, "\(functionName) needs one float")
            }
            return .returned(.float(body(value)))
        })
    }

    private static func registerRoundedInteger(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @Sendable (Double) -> Double
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Math",
            functionName: functionName
        ) { call, _ in
            guard let value = float(call, at: 0) else {
                return failure(call, "\(functionName) needs one float")
            }
            let rounded = body(Double(value))
            guard
                rounded.isFinite,
                rounded >= Double(Int32.min),
                rounded <= Double(Int32.max)
            else {
                return failure(call, "\(functionName) result is outside Int")
            }
            return .returned(.integer(Int32(rounded)))
        })
    }
}
