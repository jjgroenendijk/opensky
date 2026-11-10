// A test host base that holds the renderer slot many session hosts require. A test host
// that inherits it needs no import of the renderer module, which keeps that module's
// stability count to the targets that use it (rule 13, docs/decisions/modular-architecture.md).

public import OpenSkyRendering

@MainActor
open class RendererSlotHost {
    public var renderer: (any RendererPort)?

    public init() {}
}
