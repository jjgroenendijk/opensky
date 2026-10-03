// The data a story-manager event carries, which the Event Data run-on (7) and
// `GetEventData` (576) read. Member codes are xEdit dev-4.1.6
// `wbEventMemberEnum`; docs/engine/story-manager.md has the event table.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public struct StoryEventData: Equatable, Sendable {
    /// Two ASCII bytes, low byte first: `R1` is 0x3152.
    public enum Member: UInt16, CaseIterable, Sendable {
        case actor1 = 0x3152
        case actor2 = 0x3252
        case createdObject = 0x314F
        case form = 0x3146
        case keyword = 0x314B
        case location1 = 0x314C
        case location2 = 0x324C
        case quest = 0x3151
        case value1 = 0x3156
        case value2 = 0x3256
    }

    /// The SMEN code, such as `KILL`.
    public var event: FourCC
    public var actor1: ReferenceKey?
    public var actor2: ReferenceKey?
    public var createdObject: ReferenceKey?
    public var form: FormID?
    public var keyword: FormID?
    public var location1: ResolvedFormID?
    public var location2: ResolvedFormID?
    public var quest: FormID?
    public var value1: Float = 0
    public var value2: Float = 0

    public init(event: FourCC) {
        self.event = event
    }

    /// The reference a member names, or nil for a member that is not a reference.
    public func reference(_ member: Member) -> ReferenceKey? {
        switch member {
        case .actor1: actor1
        case .actor2: actor2
        case .createdObject: createdObject
        default: nil
        }
    }

    /// A form member as a FormID: the keyword, form, or quest.
    public func formID(_ member: Member) -> FormID? {
        switch member {
        case .form: form
        case .keyword: keyword
        case .quest: quest
        default: nil
        }
    }

    public func location(_ member: Member) -> ResolvedFormID? {
        switch member {
        case .location1: location1
        case .location2: location2
        default: nil
        }
    }
}

nonisolated extension ConditionFunctions {
    /// 576 `GetEventData`. Parameter 1 packs the event function (low 16 bits) and
    /// the member (high 16 bits); parameter 2 is the data form.
    /// (<https://ck.uesp.net/wiki/GetEventData>, xEdit `wbEventFunctionEnum`.)
    public static func installEventData(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 576, name: "GetEventData", parameter1: .integer, parameter2: .formID
        ) { call in
            let word = call.condition.parameter1.rawValue
            guard
                let event = call.context.event,
                let member = StoryEventData.Member(rawValue: UInt16(truncatingIfNeeded: word >> 16))
            else {
                return .failure(.unresolvedParameter(576))
            }
            let data = call.condition.parameter2.asFormID
            switch word & 0xFFFF {
            case 0: return eventIsID(call, event: event, member: member, data: data)
            case 2: return eventValue(event: event, member: member)
            case 3 where member == .keyword: return .success(isTrue(event.keyword == data))
            default: return .failure(.unresolvedParameter(576))
            }
        })
    }

    private static func eventIsID(
        _ call: ConditionCall,
        event: StoryEventData,
        member: StoryEventData.Member,
        data: FormID
    ) -> Result<Float, ConditionFailure> {
        if let key = event.reference(member) {
            guard let entry = call.context.references[key] else {
                return .failure(.unresolvedReference(.eventData))
            }
            return .success(isTrue(baseForm(of: entry) == data))
        }
        if let form = event.formID(member) {
            return .success(isTrue(form == data))
        }
        return .failure(.unresolvedParameter(576))
    }

    private static func eventValue(
        event: StoryEventData,
        member: StoryEventData.Member
    ) -> Result<Float, ConditionFailure> {
        switch member {
        case .value1: .success(event.value1)
        case .value2: .success(event.value2)
        default: .failure(.unresolvedParameter(576))
        }
    }
}
