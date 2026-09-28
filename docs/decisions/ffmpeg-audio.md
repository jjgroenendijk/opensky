---
type: Decision
title: ffmpeg for audio decode
description: Vendor a minimal decode-only LGPL ffmpeg built from source, link it through a
  system-library module map, embed the three dylibs in the app bundle, and share one prefix across
  worktrees - with why Homebrew's build and every alternative were rejected.
tags: [decision, audio, dependency, licensing, ffmpeg]
---

# ffmpeg for audio decode

Skyrim ships its sound and music as `.xwm` files: an xWMA container holding Windows Media Audio 2
packets. Nothing in Apple's frameworks decodes that codec. This page covers which ffmpeg, how it is
linked, and what happens when it is missing.

## Decision

- Build ffmpeg 8.1.2 from source with `tools/vendor-ffmpeg.sh`, run by `make bootstrap` or alone as
  `make ffmpeg`. The prefix is `.vendor/ffmpeg`, which is gitignored: the tarball, build tree, and
  dylibs never enter the repository.
- Configure it decode-only and LGPL-only. The result is three libraries, `libavutil`,
  `libavcodec`, and `libswresample`, about 1.2 MB, with one decoder (`wmav2`), no external libraries,
  and nothing outside `libSystem` and the OS frameworks.
- Link it through a system-library module map, `tools/ffmpeg/module.modulemap`, so the few files
  that need it write `import CFFmpeg`.
- ffmpeg is a hard build requirement. A missing prefix fails the build with a message naming
  `make bootstrap`, and the app bundle carries its own copies of the dylibs.
- Every ffmpeg type stays behind `Sources/OpenSkyEngine/Audio/WMADecoder.swift`. Callers pass container
  fields and `Data`, and get interleaved 32-bit float PCM or a typed error. A vanilla music track
  decodes to about 37 MB, so besides the call that returns a whole track there is a streaming call
  that hands each chunk to a callback. Sweeps and playback use streaming and drop each chunk.

## Why not Homebrew's ffmpeg

Homebrew's build is configured with `--enable-version3 --enable-gpl --enable-libx264
--enable-libx265 --enable-libsvtav1 ...`. `--enable-gpl` links x264 and x265 into `libavcodec`, so
that dylib is GPLv3, not LGPL. The GPL covers static and dynamic linking alike; only the LGPL gives
the dynamic linking exemption. Linking it would make a redistributed OpenSky GPLv3, which breaks the
`AGENTS.md` rule that dependency licenses stay compatible with redistributing our code.

Its dependency closure is a second problem. `otool -L` on Homebrew's `libavcodec` pulls in about
fifteen third-party dylibs (x264, x265, SVT-AV1, dav1d, libvpx, lame, opus, openssl, and more), all
encoders or formats OpenSky never uses, each at an absolute Homebrew path with no `@rpath`. Homebrew
also changes the soname on every major release, so an app pinned to one would break at launch after
an upgrade.

## The vendored build

The script downloads the release tarball and checks its SHA-256 against a pinned value. ffmpeg.org
publishes only detached GPG signatures, so the value was cross-checked with the hash Homebrew pins
for the same file. It configures:

```text
--disable-everything --disable-gpl --disable-nonfree --disable-autodetect
--disable-programs --disable-doc --disable-network --disable-avdevice --disable-avfilter
--disable-avformat --disable-swscale --disable-static --enable-shared
--enable-decoder=wmav2 --install-name-dir=@rpath
```

Three flags carry the weight:

- `--disable-autodetect` stops `configure` from picking up whatever is installed on the build
  machine. That, not `--disable-gpl` alone, guarantees no third-party code.
- `--disable-avformat` drops the demuxers. OpenSky parses the xWMA container itself and passes the
  codec fields, which is why the decoder takes `WAVEFORMATEX`-shaped fields and not a file.
- `--install-name-dir=@rpath` makes the dylibs relocatable, so embedding them is a copy, not an
  `install_name_tool` rewrite.

The script then checks the license instead of trusting the flags. A small probe against the new
prefix asserts that `avutil_license()` reports `LGPL version 2.1 or later`, that
`avcodec_configuration()` has `--disable-gpl` and `--disable-nonfree` and no `--enable-gpl`,
`--enable-nonfree`, `--enable-version3`, or `--enable-lib*`, and that the WMAv2 decoder exists.
`otool -L` over each dylib fails on anything outside `@rpath`, `/usr/lib`, and `/System`. A stamp
file makes reruns free.

## LGPL obligations

LGPL 2.1 lets a work that is not LGPL use the library, if the user can replace the library with a
changed version. OpenSky meets that three ways: the library is linked dynamically, so a new dylib
needs no relinking; the copies in `OpenSky.app/Contents/Frameworks` are plain files a user can
overwrite; and `tools/vendor-ffmpeg.sh` is the complete recipe, pinned to one upstream release. No
ffmpeg source is changed, so there are no changes to publish. A redistributed app must carry the LGPL
text and this notice, which is a packaging task for when binaries first ship.

## Linkage

The module map declares a `[system]` module `CFFmpeg` over `tools/ffmpeg/shim.h`, which includes the
few headers the decoder uses. `SWIFT_INCLUDE_PATHS` lists `tools/ffmpeg` and
`.vendor/ffmpeg/include`, so every target that compiles the audio sources finds the module, including
the unit test bundle through `@testable import OpenSky`. The app and CLI carry the link settings
themselves: `LIBRARY_SEARCH_PATHS` into the prefix and `-lavcodec -lavutil -lswresample`.

The module map has no `link` directives on purpose. Autolinking would make every target that imports
the module link `-lavcodec`, including the test bundle, which gets the symbols from its
`BUNDLE_LOADER` host instead.

Two alternatives were rejected. Adding an umbrella shim to a header every file sees grows that header
and hard-codes the prefix in a checked-in file. A SwiftPM system-library package would bring the
project's first package references and framework build phase, and gains nothing over a module map
for a library that is not fetched from a registry.

## Build phases

Two script phases run `tools/ffmpeg/xcode-phase.sh`:

- `check` runs first in the app and the CLI, and fails with a clear message when `.vendor/ffmpeg` is
  missing, instead of a raw `library not found for -lavcodec`.
- `embed` runs last in the app. It copies each dylib under its own install name into
  `Contents/Frameworks` and signs it. The app has `@executable_path/../Frameworks` in its runpath,
  and the CLI has a runpath into the vendored prefix.

`ENABLE_USER_SCRIPT_SANDBOXING` stays on, and the sandbox lets a phase touch only the paths it
lists. The dylib names carry version numbers owned by the build script, not the project file, so the
script writes `embed-inputs.xcfilelist` and `embed-outputs.xcfilelist` beside the prefix, and the
phase declares those. The output list also names the `.cstemp` file `codesign` writes through, or
signing is denied.

Xcode resolves every phase's declared inputs before it runs any phase, `check` included. So a
missing `.xcfilelist` fails planning with a raw missing-input error before `check` can print its
message. A fresh linked worktree has no `.vendor` at all, which is how this showed up. So
`tools/ffmpeg/link-vendor.sh` writes empty placeholder lists whenever the prefix has no `lib/`
folder, and a real build's lists are never overwritten.

No phase is marked always out of date, because that re-copied and re-signed the dylibs on every
no-op build and forced Xcode to re-sign the whole app. `embed` tracks its two lists. Each `check`
phase touches a stamp file, `$(DERIVED_FILE_DIR)/ffmpeg-check-$(TARGET_NAME).stamp`, as its output,
because a phase with no outputs always runs. Each phase declares `embed-inputs.xcfilelist` both as a
file list (so the dylibs are tracked) and as a plain input (so the list's own content is tracked).
A directory input would not work: a folder's modification time changes only when entries are added
or removed, so a dylib rebuilt in place would not trigger the phase. The placeholder rewrite changes
the list's time, so a removed prefix still re-runs `check` and prints the message.

## Linked worktrees

The prefix depends only on the pinned version and flags, so every worktree would build a byte-equal
copy. Instead, `link-vendor.sh` finds the main checkout with `git rev-parse --git-common-dir` and,
when a linked worktree has no `.vendor` of its own, makes `.vendor` a symlink to the main checkout's.
The project's `$(SRCROOT)/.vendor` then resolves to the shared prefix. An existing `.vendor` is left
alone, so a worktree built with `OPENSKY_FFMPEG_FORCE=1` keeps its copy.

`make vendor-link` runs the linker, and every building and testing target depends on it.
`make vendor-prune` replaces a worktree's own `.vendor` with the symlink, but only when the shared
prefix already has all three dylibs. Do not run it while a worktree is building, because the
libraries would move mid-build. A checkout opened straight in Xcode, with no `make` target ever run,
still fails on the missing list, because `make` creates both the symlink and the placeholders.

## Runtime failure, not build failure

`dlopen` and weak linking were rejected. They exist to survive a library that is missing at run
time, which an embedded copy rules out, and `dlopen` needs hand-written function pointer types for
every symbol, a quiet place to get the ABI wrong. Real failures (no output device, a corrupt file,
an unsupported codec variant) are thrown decoder errors, and the audio panel shows an unavailable
state.

## No alternative removes the dependency

- Apple frameworks: `afconvert -hf` lists no WMA variant, and Core Audio has never shipped a Windows
  Media decoder on macOS, so `AVAudioFile` cannot open an `.xwm` payload.
- [SwiftFFmpeg](https://github.com/sunlubo/SwiftFFmpeg) (MIT) still needs ffmpeg installed, leaves the
  license choice to us, and its README warns the API "is not guaranteed to be stable and is subject
  to change without warning".
- [FFmpegKit fork](https://swiftpackageindex.com/kingslay/FFmpegKit) and
  [FFmpeg-iOS](https://github.com/kewlbear/FFmpeg-iOS) ship prebuilt binaries, so someone else's
  `configure` flags decide the license. The original FFmpegKit was retired and its binaries pulled on
  2025-04-01.
- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) (MIT) covers FLAC, Ogg, MP3, WavPack, and
  Monkey's Audio, but not WMA, and it is a file player, not 3D game audio.
- A clean-room WMAv2 decoder means MDCT and large coefficient tables: weeks of DSP work for no visible
  gain. FAudio, solving the same XAudio2 problem, concluded in
  [FAudio issue 32](https://github.com/FNA-XNA/FAudio/issues/32) that "the likelihood of us ever
  getting a permissively-licensed WMA/xWMA decoder is close to zero", and used ffmpeg.

The `AGENTS.md` rule for C interop, used only where a format needs it and wrapped behind a Swift
interface, is met by the decoder wrapper.
