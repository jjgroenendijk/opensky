---
type: Decision
title: ffmpeg for audio decode
description: Vendor a minimal decode-only LGPL ffmpeg built from source, link it through a
  system-library module map, and embed the three dylibs in the app bundle.
tags: [decision, audio, dependency, licensing, ffmpeg]
timestamp: 2026-07-25T00:00:00Z
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
A missing prefix makes those declared paths vanish, which Xcode tolerates, so the friendly
`check` message still wins the race.

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
