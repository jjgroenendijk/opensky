---
type: Decision
title: ffmpeg for audio decode
description: Vendor a minimal decode-only LGPL ffmpeg built from source, link it through a
  system-library module map, and embed the three dylibs in the app bundle.
tags: [decision, audio, dependency, licensing, ffmpeg]
timestamp: 2026-08-04T00:00:00Z
---

# ffmpeg for audio decode

OpenSky's first external native dependency. Skyrim ships its sound and music as `.xwm`
files, an xWMA container carrying Windows Media Audio 2 packets, and nothing in the Apple
frameworks can decode that codec. This decision covers which ffmpeg, how it is linked, and
what happens when it is absent.

## Decision

* Build ffmpeg 8.1.2 from source with `tools/vendor-ffmpeg.sh`, run by `make bootstrap`
  and available on its own as `make ffmpeg`. The prefix is `.vendor/ffmpeg`, which is
  gitignored: the tarball, the build tree and the dylibs never enter the repository.
* Configure it decode-only and LGPL-only. The result is exactly three libraries —
  `libavutil`, `libavcodec`, `libswresample` — 1.2 MB in total, one decoder (`wmav2`),
  zero external libraries, and no dependency outside `libSystem` and the OS frameworks.
* Link it through a system-library module map at `tools/ffmpeg/module.modulemap`, giving
  `import CFFmpeg` in the few files that need it.
* Treat ffmpeg as a hard build requirement. A missing prefix fails the build with a
  message naming `make bootstrap`, and the app bundle carries its own copies of the three
  dylibs so the installed app is self-contained.
* Keep every ffmpeg type behind `opensky/Audio/WMADecoder.swift`. Callers pass container
  metadata and `Data`, and receive interleaved 32-bit float PCM or a typed error. The
  static `decode(packets:parameters:)` comes in two overloads: an accumulating one that
  returns the whole track as one `[Float]`, and a streaming one that hands each non-empty
  PCM chunk to a callback. The streaming overload exists because a vanilla music track
  decodes to roughly 37 MB, so whole-file accumulation is a memory hazard for corpus
  sweeps and playback; those paths use the streaming overload (or the per-packet instance
  `decode(packet:)` over a lazy packet source) and discard each chunk as they go (issue
  #218).

## Why not Homebrew's ffmpeg

`ffmpeg 8.1.2_1` is installed on the development machine, and using it was the assumption
recorded on 2026-07-20. That assumption does not survive contact with the actual build,
which reports:

```text
--enable-version3 --enable-gpl --enable-libx264 --enable-libx265 --enable-libsvtav1 ...
```

`--enable-gpl` links x264 and x265 into `libavcodec`, so that dylib is distributed under
GPLv3 rather than LGPL. The GPL covers linking whether it is static or dynamic; only the
LGPL grants the dynamic-linking exemption people usually have in mind. Linking it would
make a redistributed OpenSky GPLv3, which conflicts with the AGENTS.md requirement that
dependency licenses stay compatible with redistributing our own code. Nothing is triggered
while the build never leaves one machine, but the engine is meant to be redistributable.

The dependency closure is a second, independent problem. `otool -L` on Homebrew's
`libavcodec.62.dylib` pulls in x264, x265, SVT-AV1, dav1d, libvpx, lame, opus and openssl
among others: roughly fifteen third-party dylibs, all of them encoders or formats OpenSky
will never invoke, every install name an absolute Homebrew path with no `@rpath`. Bundling
that means shipping a whole media stack plus a TLS library in order to decode WMAv2, and
rewriting install names across the entire closure. Homebrew also bumps the soname on every
major release, so an installed app pinned to `libavcodec.62.dylib` would break at launch on
the next upgrade.

## The vendored build

`tools/vendor-ffmpeg.sh` downloads the release tarball, verifies its SHA-256 against a
pinned value (cross-checked with the hash Homebrew pins for the same file, because
ffmpeg.org publishes only detached GPG signatures), and configures:

```text
--disable-everything --disable-gpl --disable-nonfree --disable-autodetect
--disable-programs --disable-doc --disable-network --disable-avdevice --disable-avfilter
--disable-avformat --disable-swscale --disable-static --enable-shared
--enable-decoder=wmav2 --install-name-dir=@rpath
```

The flag set was tuned empirically from `--disable-everything`, adding back only what the
decode path needs. Three points are load-bearing:

* `--disable-autodetect` stops `configure` from picking up whatever happens to be installed
  on the build machine. That, not the `--disable-gpl` flag alone, is what guarantees the
  result contains no third-party code.
* `--disable-avformat` drops libavformat entirely. OpenSky parses the xWMA container itself
  and hands `WMADecoder` the codec parameters, so no demuxer is needed; this is also why
  the decoder's API takes `WAVEFORMATEX`-shaped fields rather than a file.
* `--install-name-dir=@rpath` makes the dylibs relocatable, so embedding them is a copy
  rather than an `install_name_tool` rewrite of a dependency graph.

The script then verifies the licensing claim rather than trusting the flags: it compiles a
small probe against the freshly built prefix and asserts that `avutil_license()` reports
`LGPL version 2.1 or later`, that `avcodec_configuration()` contains `--disable-gpl` and
`--disable-nonfree` and matches no `--enable-gpl`, `--enable-nonfree`, `--enable-version3`
or `--enable-lib*`, and that the WMAv2 decoder is present. Finally it runs `otool -L` over
each dylib and fails if anything outside `@rpath`, `/usr/lib` and `/System` appears. A full
build takes about 25 seconds including the download; a stamp file makes reruns free.

## LGPL obligations, and how this satisfies them

LGPL 2.1 lets a work that is not itself LGPL use the library, provided the user can replace
the library with a modified version. OpenSky meets that in three ways: the library is
dynamically linked, so replacing the dylib requires no relinking of OpenSky; the embedded
copies in `opensky.app/Contents/Frameworks` are ordinary files a user can overwrite with
their own build; and `tools/vendor-ffmpeg.sh` is the complete, reproducible recipe that
produced them, pinned to a specific upstream release. No ffmpeg source is modified, so
there are no changes to publish. Redistribution of a built app must carry the LGPL text and
this notice; that is a packaging obligation to honour when the project first ships binaries.

## Linkage mechanism

`tools/ffmpeg/module.modulemap` declares a `[system]` module `CFFmpeg` over
`tools/ffmpeg/shim.h`, which includes the handful of ffmpeg headers the decoder uses.
`SWIFT_INCLUDE_PATHS` on both project-level configurations lists `tools/ffmpeg` and
`.vendor/ffmpeg/include`, so the module is found by every target that compiles the audio
sources — including the unit-test bundle, which sees the audio types through
`@testable import opensky`. The app and `openskycli` targets carry the link settings
themselves: `LIBRARY_SEARCH_PATHS` into the prefix and `OTHER_LDFLAGS` of `-lavcodec
-lavutil -lswresample`, in all four of their build configurations.

The module map deliberately declares no `link` directives. Autolinking would make every
target that merely imports the module emit `-lavcodec`, including the test bundle, which
has no business owning library search paths; it resolves the symbols through its
`BUNDLE_LOADER` host instead.

Two rejected alternatives, for the record. Extending the existing `ShaderTypes.h` bridging
header with an umbrella shim is lower friction but grows a header every file in the project
sees, and hard-codes the prefix into a checked-in header. A SwiftPM system-library package
would introduce the project's first `packageReferences`, first
`XCSwiftPackageProductDependency` and first non-empty `PBXFrameworksBuildPhase`, and buys
nothing over a module map for a library that is not fetched from a registry.

## Build phases and the sandbox

Two shell script phases run `tools/ffmpeg/xcode-phase.sh`. A `check` phase runs first in
both the app and `openskycli` and fails with an actionable message when `.vendor/ffmpeg` is
absent, in place of a raw `library not found for -lavcodec`. An `embed` phase runs last in
the app, copying each dylib under its own install name into
`Contents/Frameworks` and code-signing it; the app already carries
`@executable_path/../Frameworks` in `LD_RUNPATH_SEARCH_PATHS`, and `openskycli` gained a
runpath pointing straight at the vendored prefix.

`ENABLE_USER_SCRIPT_SANDBOXING` is `YES` project-wide and stays that way, which constrains
how the embed phase is declared: the sandbox grants a phase access only to the exact paths
it lists. The dylib file names carry version numbers that belong to the build script rather
than to the project file, so `tools/vendor-ffmpeg.sh` emits `embed-inputs.xcfilelist` and
`embed-outputs.xcfilelist` next to the prefix and the phase declares those. The output list
also names the `.cstemp` sibling `codesign` writes through, without which signing is denied.
A missing prefix does not make those declared paths vanish. Xcode resolves every build
phase's declared inputs before it runs any phase, `check` included, and a missing
`.xcfilelist` fails that resolution with a raw missing-input error instead of running the
`check` phase's friendly message. Issue #275 is the evidence: a linked git worktree starts
with no `.vendor` at all, so `$(SRCROOT)/.vendor/ffmpeg/embed-inputs.xcfilelist` did not
exist and the build died during planning, before `check` ever ran.

### Staying out of the way of an incremental build

All three phases were originally declared `alwaysOutOfDate = 1`, which told Xcode to run
them on every build no matter what had changed. That made every no-op `make build` re-copy
and re-sign the three dylibs, dirty `Contents/Frameworks`, and so force Xcode to re-sign the
whole app bundle. Issue #338 removed the flag from all three and gave each phase real
dependency tracking instead.

The `embed` phase already declared the right inputs and outputs through its two
`.xcfilelist` files; dropping the flag simply lets them do their job. The `check` phases
declared no outputs at all, and a script phase with no declared outputs is out of date by
definition, so each gained a stamp file:

```text
outputPaths = (
    "$(DERIVED_FILE_DIR)/ffmpeg-check-$(TARGET_NAME).stamp",
);
```

with `touch "$SCRIPT_OUTPUT_FILE_0"` appended to the script. A clean build has no stamp, so
the validation still runs before anything can fail on a missing library.

All three phases previously listed the directory `$(SRCROOT)/.vendor/ffmpeg/lib` as an
input. Xcode compares modification times, and a directory's mtime changes only when entries
are added or removed, so a dylib rebuilt in place would not have re-triggered the phase.
Each phase now declares `embed-inputs.xcfilelist`, which names the resolved, version-numbered
dylibs, both as an `inputFileListPaths` entry (so the dylibs themselves are tracked) and as a
plain `inputPaths` entry (so the list file's own contents are tracked). That second entry is
what preserves the friendly missing-prefix message: `tools/ffmpeg/link-vendor.sh` truncates
the list to a placeholder whenever the prefix has no `lib/` directory, which changes the
file's mtime and re-runs `check` even though its stamp survives from an earlier build.

Verified against the real build: a clean build embeds and validates; touching a dylib under
`.vendor/ffmpeg/lib` re-runs both `check` and `embed`; a second `make build` or `make cli`
runs no script phase and no `CodeSign` step; and removing the prefix still fails with
`error: vendored ffmpeg missing at ... run 'make bootstrap'`.

### Linked worktrees

A linked worktree building the vendored prefix from scratch would produce a byte-identical
copy of the main checkout's, since the artifact depends only on the pinned `FFMPEG_VERSION`
and build flags, nothing in the working tree. Rebuilding it anyway would cost minutes and
hundreds of megabytes per worktree for nothing, so linked worktrees share the one prefix the
main checkout owns instead.

`tools/ffmpeg/link-vendor.sh` finds the shared root with `git rev-parse --git-common-dir`
and, when this checkout is a linked worktree without its own `.vendor`, symlinks
`.vendor -> <main checkout>/.vendor`. `$(SRCROOT)/.vendor` in the Xcode project keeps working
unmodified because the symlink makes it resolve straight through to the shared prefix. An
existing `.vendor` is left untouched, so a worktree that deliberately holds its own copy
(built with `OPENSKY_FFMPEG_FORCE=1`, or created before this script existed) keeps it.

The placeholder `embed-inputs.xcfilelist` and `embed-outputs.xcfilelist` matter for the same
input-resolution ordering described above: a worktree that has never run `make ffmpeg`
follows the symlink into a shared prefix with no `lib/` yet, so the declared `.xcfilelist`
inputs still do not exist. `link-vendor.sh` writes them empty in that case, which is enough
for Xcode to finish planning and run the `check` phase, whose actionable "run `make
bootstrap`" message can then win the race as intended. Both scripts only ever write the
placeholders when the prefix has no `lib/` directory, so a real build's file lists are never
overwritten.

`make vendor-link` runs the linker directly, and `build`, `cli`, `test`, `test-one`,
`test-ui`, and `install` all depend on it, so no manual step is needed in a fresh worktree.
Older worktrees created before this existed, or forced to build their own copy, can still
hold a full per-worktree `.vendor`; `make vendor-prune`
(`tools/ffmpeg/prune-vendor.sh`) walks `git worktree list`, refuses to touch anything unless
the shared prefix already has all three dylibs, and otherwise replaces each worktree's real
`.vendor` with a symlink to the shared one. It is not safe to run against a worktree that is
building at that moment, since its libraries would move mid-build and fail that one build;
run it when the machine is idle.

One case is not covered: a checkout that has never had any `make` target run in it, opened
straight in Xcode.app without going through the Makefile first, still fails on the missing
`.xcfilelist`. `make` is what creates both the symlink and the placeholders, so a build path
that bypasses `make` entirely bypasses the fix too.

## Runtime failure, not build failure

`dlopen` and weak linking were both rejected. They exist to survive a library that is
absent at runtime, which an embedded copy makes a non-scenario, and `dlopen` would cost
hand-written function-pointer typedefs for every symbol — a quiet place to get the ABI
wrong. Degradation belongs at the OpenSky layer instead, for failures that actually occur:
no output device, a corrupt file, an unsupported codec variant. Those surface as thrown
`WMADecoderError` values and, later, as an `unavailable(reason:)` state the audio panel
renders, matching the existing `startupErrorMessage` precedent.

## Alternatives that would have removed the dependency

None exist. Surveyed in full:

* **Apple frameworks.** `afconvert -hf` lists no WMA variant. CoreAudio has never shipped a
  Windows Media decoder on macOS, so `AVAudioFile` cannot open an `.xwm` payload.
* **[SwiftFFmpeg](https://github.com/sunlubo/SwiftFFmpeg)** (MIT) is a `systemLibrary`
  wrapper: still needs ffmpeg installed, still leaves the GPL/LGPL choice to us, and its
  own README warns the API "is not guaranteed to be stable and is subject to change without
  warning". That is this decision's module-map approach wrapped in an unstable third-party
  surface covering all of ffmpeg, where decode-only needs about a dozen symbols.
* **[FFmpegKit fork](https://swiftpackageindex.com/kingslay/FFmpegKit)** and
  **[FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS)** ship prebuilt xcframeworks, so a
  binary blob enters the dependency graph and someone else's `configure` flags decide the
  license. The original FFmpegKit was retired with its binaries pulled on 2025-04-01.
* **[SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine)** (MIT, well maintained)
  covers FLAC, Ogg, MP3, WavPack and Monkey's Audio but not WMA, and it is a file-playback
  engine rather than 3D game audio.
* **A clean-room WMAv2 decoder** means MDCT plus large coefficient VLC tables: weeks of DSP
  work, subtle-audio-bug risk, no user-visible gain. FAudio, solving the identical XAudio2
  problem, concluded in [issue #32](https://github.com/FNA-XNA/FAudio/issues/32) that "the
  likelihood of us ever getting a permissively-licensed WMA/xWMA decoder is close to zero",
  and used ffmpeg.

AGENTS.md's dependency ladder — "C/C++ only when no reasonable Swift option exists, wrapped
behind a Swift interface" — is satisfied by the wrapper we write ourselves.

## Verification

The vendored library was verified as described above, and the decoder was exercised end to
end through a throwaway probe (never committed, per the probe rules):

* A synthetic 440 Hz stereo sine, encoded locally to WMAv2, decoded to 88,064 frames at
  44,100 Hz stereo, 1.9969 s against a container duration of 1.999 s, non-silent.
* One real `.xwm` read out of the player's own install decoded to 4,655,104 frames at
  44,100 Hz stereo, 105.55791383 s against a container duration of 105.557914 s.

Committed coverage is `openskyTests/WMADecoderTests.swift` over synthetic headers and
deterministic noise payloads: header rejection, the typed error surface, garbage packets
that must not crash, and repeated construction and failed-construction loops that exercise
the allocate-and-free pairing. No game audio, decoded or otherwise, enters the repository.
