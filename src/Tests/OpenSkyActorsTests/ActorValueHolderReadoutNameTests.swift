// The name an actor-value readout shows for a holder: the NPC_ base FormID is what the
// user types into the record dump.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import Testing

struct ActorValueHolderReadoutNameTests {
    @Test func eachSubjectNamesItselfForTheRecordDump() {
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x1234)
        #expect(ActorValueHolder.player.readoutName == "Player")
        let actor = ActorValueHolder(key: key, subject: .actor(base: FormID(0x42)))
        #expect(actor.readoutName == "\(key.description) (base \(FormID(0x42)))")
        #expect(ActorValueHolder(key: key, subject: .generated).readoutName == key.description)
    }
}
