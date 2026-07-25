// Number formatting, string-literal validation, and the 32-bit integer
// conversions the bitwise opcodes need (milestone 8.3.2). Split out of
// `AS2Coercion.swift` so both stay inside the strict-lint size caps.
//
// Reference: ECMA-262 3rd edition, section 9.8.1 "ToString Applied to the
// Number Type", section 9.3.1 "ToNumber Applied to the String Type", section
// 9.5 "ToInt32: (Signed 32 Bit Integer)", and section 9.6 "ToUint32: (Unsigned
// 32 Bit Integer)".

import Foundation

extension AS2Coercion {
    /// The exclusive bound below which an integral number prints in positional
    /// notation rather than exponential (ECMA-262 9.8.1 step 6).
    static let positionalLimit = 1e21

    /// ECMA-262 9.8.1. Integral magnitudes below 1e21 print without a decimal
    /// point; everything else uses Swift's shortest round-trip form with the
    /// exponent normalized to the ECMAScript spelling (`1e+22`, `1.5e-7`), so
    /// no zero-padded exponent leaks into a menu string.
    static func numberToString(_ value: Double) -> String {
        if value.isNaN {
            return "NaN"
        }
        if value == 0 {
            return "0"
        }
        if value.isInfinite {
            return value < 0 ? "-Infinity" : "Infinity"
        }
        if value == value.rounded(.towardZero), abs(value) < positionalLimit {
            return String(format: "%.0f", value)
        }
        return normalizedExponent(String(value))
    }

    private static func normalizedExponent(_ text: String) -> String {
        guard let marker = text.firstIndex(of: "e") else {
            return text
        }
        let mantissa = String(text[text.startIndex ..< marker])
        var exponent = Substring(text[text.index(after: marker)...])
        var sign = "+"
        if exponent.hasPrefix("-") {
            sign = "-"
            exponent = exponent.dropFirst()
        } else if exponent.hasPrefix("+") {
            exponent = exponent.dropFirst()
        }
        while exponent.count > 1, exponent.hasPrefix("0") {
            exponent = exponent.dropFirst()
        }
        return mantissa + "e" + sign + exponent
    }

    /// `0x`-prefixed hexadecimal, the one numeric literal ActionScript accepts
    /// beyond the ECMAScript decimal grammar. Returns nil when `text` is not a
    /// hexadecimal literal at all.
    static func hexadecimalValue(_ text: Substring) -> Double? {
        guard text.hasPrefix("0x") || text.hasPrefix("0X") else {
            return nil
        }
        let digits = text.dropFirst(2)
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else {
            return Double.nan
        }
        guard let value = UInt64(digits, radix: 16) else {
            return Double.nan
        }
        return Double(value)
    }

    /// ECMA-262 9.3.1 `StrDecimalLiteral` without the sign, which the caller
    /// has already consumed. Written as an explicit scan because
    /// `Double(String)` additionally accepts `inf`, `nan`, and hexadecimal
    /// floating point, none of which are ActionScript numbers.
    static func isDecimalLiteral(_ text: Substring) -> Bool {
        var index = text.startIndex
        let digits = scanDigits(text, from: &index)
        var fractionDigits = 0
        if index < text.endIndex, text[index] == "." {
            index = text.index(after: index)
            fractionDigits = scanDigits(text, from: &index)
        }
        guard digits + fractionDigits > 0 else {
            return false
        }
        if index < text.endIndex, text[index] == "e" || text[index] == "E" {
            index = text.index(after: index)
            if index < text.endIndex, text[index] == "+" || text[index] == "-" {
                index = text.index(after: index)
            }
            guard scanDigits(text, from: &index) > 0 else {
                return false
            }
        }
        return index == text.endIndex
    }

    private static func scanDigits(_ text: Substring, from index: inout Substring.Index) -> Int {
        var count = 0
        while index < text.endIndex, text[index].isASCII, text[index].isNumber {
            count += 1
            index = text.index(after: index)
        }
        return count
    }

    /// ECMA-262 9.5.
    static func toInt32(_ value: Double) -> Int32 {
        let wrapped = wrappedTo32Bits(value)
        return Int32(truncatingIfNeeded: Int64(wrapped))
    }

    /// ECMA-262 9.6.
    static func toUInt32(_ value: Double) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64(wrappedTo32Bits(value)))
    }

    /// The shared `modulo 2^32` step of ToInt32 and ToUint32, kept in `Double`
    /// so out-of-range and non-finite inputs cannot trap.
    private static func wrappedTo32Bits(_ value: Double) -> Double {
        guard value.isFinite, value != 0 else {
            return 0
        }
        let truncated = value < 0 ? -(-value).rounded(.down) : value.rounded(.down)
        let modulo = truncated.truncatingRemainder(dividingBy: 4_294_967_296)
        return modulo < 0 ? modulo + 4_294_967_296 : modulo
    }
}
