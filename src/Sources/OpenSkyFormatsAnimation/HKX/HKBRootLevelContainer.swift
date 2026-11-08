// hkRootLevelContainer decode: the packfile's entry point. Every behavior file
// names the same root class, so a file's role comes from its named variants:
// `hkbProjectData`, `hkbCharacterData`, or `hkbBehaviorGraph`.
// Byte map and citations: docs/formats/hkx-behavior.md.

import Foundation

/// One entry of `hkRootLevelContainer::m_namedVariants`: an authored name, the
/// Havok class name of the payload, and a pointer to the payload object.
nonisolated public struct HKBNamedVariant: Equatable, Sendable {
    public let name: String?
    public let className: String?
    public let variant: HKXPointerTarget?
}

/// Decoded `hkRootLevelContainer`. `variants` is in file order; vanilla
/// behavior files carry exactly one.
nonisolated public struct HKBRootLevelContainer: Equatable, Sendable {
    public let variants: [HKBNamedVariant]
    /// Fields that did not resolve while decoding, for the census report.
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkRootLevelContainer"

    /// `m_namedVariants` hkArray at offset 0 — hkRootLevelContainer has no
    /// base class, so the array is the whole 16-byte object.
    private static let namedVariantsField = HKXField(0x00, "m_namedVariants")
    /// hkRootLevelContainerNamedVariant, 24 bytes: two hkStringPtr then a
    /// pointer.
    private static let variantStride = 24
    private static let variantNameField = HKXField(0x00, "m_name")
    private static let variantClassNameField = HKXField(0x08, "m_className")
    private static let variantField = HKXField(0x10, "m_variant")

    /// Decodes the file's root container. Returns nil when the packfile
    /// registers no `hkRootLevelContainer` object at all, which no vanilla
    /// file does — the caller reports that as a malformed file rather than
    /// guessing a role from the container header.
    public static func root(in graph: HKXObjectGraph) -> HKBRootLevelContainer? {
        guard
            let object = graph.objects(ofClass: className).first,
            var cursor = graph.cursor(at: object)
        else {
            return nil
        }
        var variants: [HKBNamedVariant] = []
        if let view = cursor.array(at: namedVariantsField) {
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: variantStride
                    )
                else {
                    continue
                }
                variants.append(HKBNamedVariant(
                    name: element.string(at: variantNameField),
                    className: element.string(at: variantClassNameField),
                    variant: element.pointer(at: variantField)
                ))
                cursor.absorb(element)
            }
        }
        return HKBRootLevelContainer(variants: variants, unresolved: cursor.unresolved)
    }

    /// The payload of the first variant whose declared class name matches.
    public func variant(ofClass name: String) -> HKXPointerTarget? {
        variants.first { $0.className == name }?.variant
    }
}
