# AGENTS.md — Sources

Rules for code under `Sources/`. The module list, the layers, and the import rules are in
`docs/tools/modules.md`; `docs/tools/swift-toolchain.md` explains the isolation patterns.

## Folder layout

- No Swift file sits loose at the root of `OpenSky/`, a multi-format `OpenSkyFormats*/`, or
  `OpenSkyWorld/`; each goes in a domain folder. `OpenSkyGameData/` and the feature modules
  are small enough to stay flat. `OpenSkyRendering/` keeps the renderer at its root and puts
  `UI/`, `Terrain/`, `Weather/`, `ImageSpace/`, `Effects/`, `TextureStreaming/`, and
  `RayTracing/` in folders.
- `OpenSky/` (app only): `Shell/` (app lifecycle, sidebar, panel framework), `Launcher/`
  (the start window and its pages), `Panels/` (one view controller per destination),
  `GameView/` (`GameViewController`, its panel forwards, the world adapters, and the menu
  controllers), and `Resources/`.
- `OpenSkyFormats*/`: one folder per format (`BSA/`, `NIF/`, `DDS/`, ...), plus `Binary/`,
  `Compression/`, and `Geometry/`. A module named after its one format (`OpenSkyFormatsESM`,
  `OpenSkyFormatsPEX`, `OpenSkyFormatsSWF`) keeps the format at its root, because a folder
  with the module's own name says nothing (`OpenSkyFormatsESM/Records/`). Its test target
  and its `OpenSkyFormatsTesting` folder follow the same layout.
- `OpenSkyWorld/`: `Actors/`, `Benchmark/`, `Camera/`, `Cells/`, `Conditions/`, `Effects/`,
  `Loading/`, `Navigation/`, `Objects/`, `Packages/`, `Player/`, `Session/`, `State/`,
  `Streaming/`, `Terrain/`, and `Weather/`.
- A panel seam, `XControlProviding.swift` or `XReadout.swift`, lives in the module of its
  domain. A seam that names a higher layer, such as menus, cameras, or scripts, lives in
  `OpenSkyMenus/`.
- A package module never imports a module above it. Behavior that needs a higher layer goes
  in an extension file up there.
- An extension file is named `Type+Feature.swift`, for example
  `Package+Schedule.swift`. File names stay unique inside a target, because Swift rejects
  two files with one name in the same module.
- Do not add a new `GameViewController+X.swift` file. Game logic there cannot be reached by
  the package tests or the CLI. Put it in a coordinator in the feature module instead;
  `docs/engine/coordinators.md` has the pattern, and `VendorCore` with `VendorCoordinator` is
  the example: a pure core and a thin shell.
- Past 600 lines (the file-length warning), split into a satellite file (`Renderer.swift` ->
  `RendererScenePass.swift`). Check first which members need same-file `private(set)`
  access. Past the parameter or tuple cap, introduce a struct.

## Swift conventions

- Swift-to-Metal shared structs go in `OpenSkyShaderTypes/ShaderTypes.h` with explicit
  `simd`-aligned layout. There is no bridging header, so a Swift file that uses one writes
  `import OpenSkyShaderTypes`. Metal shaders keep writing `#import "ShaderTypes.h"`.
- Do not build with a `SWIFT_VERSION` override; every target is in Swift 6 mode.
- The default actor isolation is `MainActor`. An extension of a `nonisolated` type is
  declared `nonisolated extension` unless it deliberately names a global actor, because the
  type's isolation does not carry into a separate extension. Isolation is per declaration,
  not per file: a `private` helper below a `nonisolated` type is main-actor isolated until
  it says otherwise.
- A declaration in a package module that other modules use is `public`. A struct another
  module builds needs an explicit `public init(...)`, because the implicit memberwise one
  stays internal. A public value type states `Sendable` itself, because Swift does not infer
  it across a module boundary.
- Every file that uses a module writes its own `import`. New modules and their dependencies
  go in `Package.swift`, never in the project file.

## Bulk edits

- Make an edit that repeats across many files with a script, then review `git diff --stat`
  and a sample of the hunks. Do not read and edit each site in the conversation. Each file
  read stays in context for the rest of the session, so per-site edits cost far more.
- Comments: `make comment-blocks PATHS='Sources/X' > .logs/comments.txt` prints only the long
  blocks, each under a `=== path:first-last` header. Rewrite the text under each header,
  leave a body empty to delete the block, then run `make comment-apply SPEC=.logs/comments.txt`.
