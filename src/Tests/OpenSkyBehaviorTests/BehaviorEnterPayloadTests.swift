// The string payloads a state's enter events carry. The headsman's state sends
// `AnimObjDraw` with the axe's ANIO editor ID, so the prop comes from here.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import Testing

struct BehaviorEnterPayloadTests {
    private static let stateInfo = 0x000
    private static let eventArray = 0x080
    private static let events = 0x0A0
    private static let payload = 0x0C0
    private static let payloadText = 0x0E0
    private static let stateName = 0x100

    /// State -> enter events [AnimObjLoad (no payload), AnimObjDraw (payload)].
    private static func graph() throws -> HKXObjectGraph {
        var fixture = HKBNodeFixture(payloadSize: 0x120)
        fixture.addObject("hkbStateMachineStateInfo", at: stateInfo)
        fixture.addObject("hkbStateMachineEventPropertyArray", at: eventArray)
        fixture.addObject("hkbStringEventPayload", at: payload)
        fixture.setPointer(at: stateInfo + 0x40, to: eventArray) // m_enterNotifyEvents
        fixture.setString("Executioner_State", at: stateInfo + 0x60, storage: stateName)
        fixture.setArray(at: eventArray + 0x10, count: 2, dataOffset: events)
        fixture.setInt32(3, at: events + 0x00)
        fixture.setInt32(4, at: events + 0x10)
        fixture.setPointer(at: events + 0x18, to: payload)
        fixture.setString("AnimObjectExecutionerAxe", at: payload + 0x10, storage: payloadText)
        return try fixture.buildGraph()
    }

    @Test func theEnterEventPayloadNamesTheProp() throws {
        let graph = try Self.graph()
        let state = try #require(HKBStateMachineStateInfo.decode(
            at: HKXPointerTarget(sectionIndex: HKBNodeFixture.dataSection, dataOffset: 0),
            in: graph
        ))
        #expect(BehaviorEventClipIndex.enterPayloads(of: state, in: graph)
            == ["AnimObjectExecutionerAxe"])
    }
}
