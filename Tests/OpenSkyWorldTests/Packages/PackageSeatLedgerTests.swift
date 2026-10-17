// PackageSeatLedger: one actor per seat, and keyed seats for keyword holders.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldInterface
import Testing

struct PackageSeatLedgerTests {
    let chair = ReferenceKey.plugin(name: "seat.esm", objectID: 10)
    let guardActor = ReferenceKey.plugin(name: "seat.esm", objectID: 1)
    let farmer = ReferenceKey.plugin(name: "seat.esm", objectID: 2)
    let guardKeyword = FormID(0x500)

    func seat(keyword: FormID? = nil) -> FurnitureSeat {
        FurnitureSeat(position: .zero, heading: 0, animationType: 1, keyword: keyword)
    }

    @Test func twoActorsNeverShareASeat() {
        var ledger = PackageSeatLedger()
        let seats = [seat()]
        let first = ledger.reserve(in: chair, seats: seats, actor: guardActor) { _ in false }
        let second = ledger.reserve(in: chair, seats: seats, actor: farmer) { _ in false }
        #expect(first?.index == 0)
        #expect(second == nil)
        #expect(ledger.holder(of: chair, index: 0) == guardActor)
    }

    @Test func aKeyedSeatWinsForItsKeywordAndIsKeptFromOthers() {
        var ledger = PackageSeatLedger()
        let seats = [seat(), seat(keyword: guardKeyword)]
        let guardSeat = ledger.reserve(in: chair, seats: seats, actor: guardActor) {
            $0 == guardKeyword
        }
        #expect(guardSeat?.index == 1)
        let farmerSeat = ledger.reserve(in: chair, seats: seats, actor: farmer) { _ in false }
        #expect(farmerSeat?.index == 0)
    }

    @Test func onlyTheHolderFreesASeat() throws {
        var ledger = PackageSeatLedger()
        let seats = [seat()]
        let held = try #require(
            ledger.reserve(in: chair, seats: seats, actor: guardActor) { _ in false }
        )
        ledger.release(held, by: farmer)
        #expect(ledger.holder(of: chair, index: 0) == guardActor)
        ledger.release(held, by: guardActor)
        #expect(ledger.holder(of: chair, index: 0) == nil)
    }
}
