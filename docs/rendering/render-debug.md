---
type: Subsystem
title: Render debug views and layer isolation
description: Function-constant-gated debug channels for the scene pass, an OptionSet layer
  mask honoured by both the scene and shadow passes, the composition rule against the
  subsystem enables, and the World > Render Debug surface.
tags: [rendering, metal, debugging, engine, app-ui]
timestamp: 2026-08-10T00:00:00Z
---

# Render debug views and layer isolation

Issue #144. The app's stated purpose is finding visual bugs, and before this there was no
way to bisect one: the only tools were reading code and staring at the frame. Two
capabilities cover most of the gap — switch the scene pass's output channel, and switch
layers off one at a time.

Both are pure OpenSky diagnostics over OpenSky's own renderer. No Bethesda code or data is
involved.

## Contents

* Debug channels — the function-constant gate, the seven modes, the five pipelines
* Layer isolation — the `RenderLayer` mask, where the tag lives, solo
* The composition rule against the subsystem enables
* Why neither persists, and why neither reaches an offscreen frame
* Surface and verification

## Debug channels

Wiring is **function constant to gate, uniform field to select**, not one or the other.

* `FunctionConstantDebugView` (`ShaderTypes.h`) is defined as `false` by every shipping
  pipeline and `true` by the five debug ones, so in a shipping pipeline the whole debug
  block folds to a compile-time `false` branch and those fragments generate the code they
  did before the channels existed.
* `FrameUniforms.debugMode` selects the channel per frame, so changing channel rebuilds no
  pipeline state.

Every pipeline built from one of the four fragments that reads the constant must set it —
including the shipping grass, terrain and water pipelines, which previously specialized
nothing. Metal requires a referenced function constant to be defined at specialization and
**aborts pipeline validation** when one is not, so leaving it undefined in the shipping
pipelines is not an option: the first attempt did exactly that and every `Renderer.init`
died with `MTLReportFailure` inside `validateWithDevice`. `Renderer.specializedFragment`
is the one place that builds these `MTLFunctionConstantValues`, so a new fragment cannot
pick up the constant without also picking up the definition.

Seven modes (`DebugViewMode` in `ShaderTypes.h`, mirrored by `RenderDebugMode` in
`opensky/Engine/Rendering/RendererDebugState.swift`):

| Mode | What it writes |
| --- | --- |
| `off` | Shipping shading; no debug pipeline is bound |
| `wireframe` | Flat wire colour, with the encoder's triangle fill mode set to `.lines` |
| `worldNormals` | World-space normal remapped from [-1, 1] to [0, 1] RGB |
| `textureCoordinates` | `fract(uv)` in red/green |
| `mipLevel` | `calculate_unclamped_lod` through a fine-cool to coarse-warm ramp |
| `shadowCascade` | One colour per sun-shadow cascade, grey past the last |
| `layerCategory` | One colour per `RenderLayerBit` |

Only **five** pipeline states are needed rather than seven modes times five geometry paths:
`DebugRenderPipelines` in `Rendering/RendererScenePipelineSetup.swift` holds
`staticMesh`, `skinned`, `terrain`, `grass` and `water`. There is no separate cutout
variant, because `updateDrawUniforms` writes `alphaThreshold: material.alphaTestThreshold ?? 0`
and a threshold of zero discards nothing, so the alpha-testing static variant serves the
opaque groups too. The water debug variant deliberately drops its shipping twin's blend
state: a debug channel answers "what is here", and blending that answer with the terrain
underneath would hide the water plane in exactly the modes meant to find it.

`shadowCascade` reuses `sunShadowCascadeIndex`, factored out of `sunShadowFactor`, so the
cascade the view draws is the cascade the shading used.

Two modes named in the issue are deliberately absent. **LOD level** would render as a binary
near/far tint, because there is no per-mesh LOD in this engine — `NIFNode.traversedTypes`
excludes `NiLODNode`/`NiSwitchNode` — and `layerCategory` already separates distant LOD for
free. **Overdraw** needs a blend-enabled pipeline set plus a depth-always state plus
per-site overrides, and the stencil alternative collides with the SWF layer's counting
stencil ops in the same encoder; it lands later behind the unchanged mode enum.

### Fill mode

Wireframe is a raster state rather than a channel, so `encodeScenePass` sets it once on the
encoder and threads the chosen mode through `ScenePassState.fillMode`. `encodeParticles`
forces `.fill` and restores that value (a wireframed billboard quad is noise), and the pass
resets to `.fill` before the world-overlay, SWF and dev-UI layers, which share the same
encoder and would otherwise draw a wireframe HUD.

## Layer isolation

`RenderLayer` (`Rendering/RendererDebugState.swift`) is one `OptionSet` whose raw values
match `RenderLayerBit` in `ShaderTypes.h` bit for bit: `statics`, `actors`, `distantLOD`,
`terrain`, `water`, `sky`, `grass`, `particles`.

`RenderScene` already partitions the frame, so `terrain`, `water`, `sky`, `grass` and
`particles` isolate at their encode sites with no new tagging. Separating statics, actors
and distant LOD inside `opaque`/`alphaTested` needs a tag, and that tag lives on
`RenderPlacement`/`DrawInstance`, **not** on `RenderMesh`: meshes are shared and cached by
VFS path in `MeshLibrary`, so mesh identity cannot own a scene role — the same tree mesh is
a static in one cell and a distant-LOD billboard in the block above it. The
`layer: RenderLayer = .statics` default leaves every ordinary construction site unchanged;
only `ActorAssembly.renderPlacements` (`.actors`) and the two distant-LOD builders
(`.distantLOD`) pass anything else. The layer joins the `GroupAccumulator` key, so a
`DrawGroup` never mixes roles and `DrawGroup.layer` is well defined.

**The shadow pass honours the same mask.** Hiding the statics while their shadows still fell
on the terrain would make the tool actively misleading, so `encodeCasterGroups` and
`encodeShadowTerrain` filter on `effectiveRenderLayers` exactly as the scene pass does.

Solo is **derived, not stored**: `RenderLayer.soloedLayer` is non-nil when the mask holds
exactly one bit. Two stores for one state desynchronise; a derived one cannot.

## Composition with the subsystem enables

`Renderer` already carries `grassEnabled`, `particlesEnabled`, `precipitationEnabled` and
friends, so a parallel set of layer booleans would be two competing controls for the same
pixels. The rule is stated once, on `RenderLayerPolicy`, and folded exactly once per frame
by `Renderer.effectiveRenderLayers` with no GPU work:

> A subsystem enable is the *feature* switch — semantic, persisted, owned by its panel
> section. The layer mask is the *view* filter — transient, never persisted, dev-only.
> Effective visibility is the AND.

`.grass` drops when grass is disabled. `.particles` drops only when both particle sources
are off, because cell particles and precipitation share one layer and one encode path; each
source is still ANDed with its own enable at its draw site.

## Not persisted, and not in an offscreen frame

Unlike `ShadowQuality`, neither the channel nor the mask survives a relaunch. A session that
starts in wireframe, or with the terrain missing, reads as a rendering bug — and telling
those two apart is the entire point of the pair.

For the same reason `renderOffscreenFrame` substitutes `RenderDebugState.production` for the
duration of the frame unless `Renderer.renderDebugAppliesOffscreen` is set, so screenshots
and bench runs stay clean however the sidebar is currently set. The device-gated tests opt
in through that flag.

## Surface

`World > Render Debug` (`opensky/App/Shell/Sections/RenderDebugSection.swift`), wired
through `RenderDebugControlProviding`. Controls: `RenderDebugModeControl` (channel),
`RenderDebugLayer<Name>Control` (one checkbox per layer, in `RenderLayer.ordered`),
`RenderDebugSoloControl` (isolation, writing the same mask the checkboxes do), readout
`RenderDebugStatsLabel`. A non-`off` channel or a mask other than `.all` lights the
`Destination-world` override indicator, and the sidebar's "Reset all" clears both.

## Verification

* `openskyTests/RenderDebugStateTests.swift` — raw values pinned against the imported
  `DebugViewMode` and `RenderLayerBit`, solo derivation, the whole `RenderLayerPolicy`
  composition rule, readout wording.
* `openskyTests/RenderDebugEncodeTests.swift` (device gated) — draw-stat deltas for the
  scene and shadow passes when a layer is isolated, an offscreen frame proving the filters
  do not leak, and a wireframe frame covering fewer pixels than the filled one.
* `openskyTests/RenderDebugSectionTests.swift` — the section built through the real registry
  factory, its pinned accessibility ids, the control round trip, and the override/reset
  contract.
* `openskyUITests/RenderDebugUITests.swift` — the ids reachable in the built view hierarchy.
