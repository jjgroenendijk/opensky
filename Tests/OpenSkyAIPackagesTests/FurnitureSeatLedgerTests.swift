// FurnitureSeatLedger: one actor per seat, keyed seats for keyword holders, and
// the marker types and the record's switched-off markers.

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
import OpenSkyWorldInterface
import Testing

struct FurnitureSeatLedgerTests {
    let chair = ReferenceKey.plugin(name: "seat.esm", objectID: 10)
    let guardActor = ReferenceKey.plugin(name: "seat.esm", objectID: 1)
    let farmer = ReferenceKey.plugin(name: "seat.esm", objectID: 2)
    let guardKeyword = FormID(0x500)

    func seat(keyword: FormID? = nil) -> FurnitureSeat {
        FurnitureSeat(position: .zero, heading: 0, animationType: 1, keyword: keyword)
    }

    @Test func twoActorsNeverShareASeat() {
        var ledger = FurnitureSeatLedger()
        let seats = [seat()]
        let first = ledger.reserve(in: chair, seats: seats, actor: guardActor) { _ in false }
        let second = ledger.reserve(in: chair, seats: seats, actor: farmer) { _ in false }
        #expect(first?.index == 0)
        #expect(second == nil)
        #expect(ledger.holder(of: chair, index: 0) == guardActor)
    }

    @Test func aKeyedSeatWinsForItsKeywordAndIsKeptFromOthers() {
        var ledger = FurnitureSeatLedger()
        let seats = [seat(), seat(keyword: guardKeyword)]
        let guardSeat = ledger.reserve(in: chair, seats: seats, actor: guardActor) {
            $0 == guardKeyword
        }
        #expect(guardSeat?.index == 1)
        let farmerSeat = ledger.reserve(in: chair, seats: seats, actor: farmer) { _ in false }
        #expect(farmerSeat?.index == 0)
    }

    @Test func onlyTheHolderFreesASeat() throws {
        var ledger = FurnitureSeatLedger()
        let seats = [seat()]
        let held = try #require(
            ledger.reserve(in: chair, seats: seats, actor: guardActor) { _ in false }
        )
        ledger.release(held, by: farmer)
        #expect(ledger.holder(of: chair, index: 0) == guardActor)
        ledger.release(held, by: guardActor)
        #expect(ledger.holder(of: chair, index: 0) == nil)
    }

    /// A double bed's L record turns marker 1 off, and a sleeper wants a sleep marker.
    @Test func aSwitchedOffMarkerIsNoOnesAndTheWantedTypeComesFirst() {
        var ledger = FurnitureSeatLedger()
        var off = seat()
        off.isEnabled = false
        let bed = FurnitureSeat(position: [50, 0, 0], heading: 0, animationType: 2, keyword: nil)
        let seats = [seat(), off, bed]
        let sleeper = ledger.reserve(in: chair, seats: seats, actor: farmer, animation: 2) { _ in
            false
        }
        #expect(sleeper?.index == 2)
        let sitter = ledger.reserve(in: chair, seats: seats, actor: guardActor, animation: 2) { _ in
            false
        }
        #expect(sitter?.index == 0)
        #expect(ledger.reserve(in: chair, seats: seats, actor: .player) { _ in false } == nil)
    }

    @Test func theNearestSeatWinsAndReleaseAllFreesEverySeat() {
        var ledger = FurnitureSeatLedger()
        let near = FurnitureSeat(position: [100, 0, 0], heading: 0, animationType: 1, keyword: nil)
        let seats = [seat(), near]
        let taken = ledger.reserve(in: chair, seats: seats, actor: farmer, near: [90, 0, 0]) { _ in
            false
        }
        #expect(taken?.index == 1)
        #expect(ledger.holders(of: chair) == [1: farmer])
        ledger.releaseAll(heldBy: farmer)
        #expect(ledger.holders(of: chair).isEmpty)
    }
}
