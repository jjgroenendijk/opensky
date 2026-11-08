// Papyrus name folding: the ASCII fast path gives the same answers as lowercasing.

import OpenSkyScriptingInterface
import Testing

struct PapyrusNameTests {
    private static let names = [
        "OnActivate", "onactivate", "ONACTIVATE", "OnActivat", "OnInit", "", "_x", "_X",
        "Größe", "GRÖSSE", "größe", "Äpfel", "äpfel", "Name1", "name1", "naMe2", "@[`{"
    ]

    @Test func matchesAgreesWithLowercasedComparison() {
        for left in Self.names {
            for right in Self.names {
                #expect(
                    PapyrusName.matches(left, right) == (left.lowercased() == right.lowercased()),
                    "\(left) vs \(right)"
                )
            }
        }
    }

    @Test func keyAgreesWithLowercased() {
        for name in Self.names {
            #expect(PapyrusName.key(name) == name.lowercased())
        }
    }
}
