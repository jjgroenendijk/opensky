// `$KEY{argument}` expansion over an in-code table.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct TranslationTokenTests {
    private let table = [
        "$Hits for {} damage.": "Enemy hits you for {} damage.",
        "$Gold": "Septims",
        "$Pair{}{}": "{} and {}",
        "$One{}": "only {} then {}"
    ]

    private func expand(_ token: String) -> String {
        TranslationToken.expand(token) { table[$0] }
    }

    @Test func fillsTheArgumentIntoItsSlot() {
        #expect(expand("$Hits for {10} damage.") == "Enemy hits you for 10 damage.")
    }

    @Test func expandsAnArgumentThatIsAToken() {
        #expect(expand("$Pair{$Gold}{3}") == "Septims and 3")
    }

    @Test func expandsANestedArgumentToken() {
        #expect(expand("$Pair{$Hits for {7} damage.}{x}") == "Enemy hits you for 7 damage. and x")
    }

    @Test func exactKeyWinsOverArguments() {
        #expect(expand("$Hits for {} damage.") == "Enemy hits you for {} damage.")
    }

    @Test func unknownKeyStaysAsWritten() {
        #expect(expand("$Missing{4}") == "$Missing{4}")
        #expect(expand("$Missing") == "$Missing")
        #expect(expand("No dollar {4}") == "No dollar {4}")
    }

    @Test func unpairedBracesStayAsWritten() {
        #expect(expand("$Pair{a}{b") == "$Pair{a}{b")
        #expect(expand("$Pair}a{") == "$Pair}a{")
    }

    @Test func extraSlotsStayEmptyBraces() {
        #expect(expand("$One{5}") == "only 5 then {}")
    }

    @Test func emptyArgumentFillsNothing() {
        #expect(expand("$One{}") == "only {} then {}")
        #expect(expand("$Pair{}{b}") == " and b")
    }

    @Test func parseSplitsKeyAndArguments() throws {
        let parsed = try #require(TranslationToken.parse("$A{x}b{$C{1}}"))
        #expect(parsed.key == "$A{}b{}")
        #expect(parsed.arguments == ["x", "$C{1}"])
        #expect(TranslationToken.parse("$A") == nil)
    }
}
