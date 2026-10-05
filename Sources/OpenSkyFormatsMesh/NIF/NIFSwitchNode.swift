// NiSwitchNode: a NiNode that draws one child, the active one. Flora keeps its
// unharvested and harvested variants under one. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFSwitchNode: Sendable {
    public static let typeName = "NiSwitchNode"

    public let object: NIFObjectPrefix
    public let children: [Int32]
    public let flags: UInt16
    public let activeIndex: UInt32

    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        object = try NIFObjectPrefix(reader: &reader, header: header)
        children = try NIFNode.readRefs(&reader, label: "child")
        _ = try NIFNode.readRefs(&reader, label: "effect")
        flags = try reader.readUInt16()
        activeIndex = try reader.readUInt32()
    }

    /// The active child only. An index past the child list draws nothing.
    public var activeNode: NIFNode {
        let index = Int(activeIndex)
        let active = children.indices.contains(index) ? [children[index]] : []
        return NIFNode(object: object, children: active)
    }
}
