#!/bin/sh
# The structural rules in tools/syntax-lint/, over the Swift files the branch changed, or
# every one in CI. Each rule walks the syntax tree, so a comment or a string never matches.
# The checker is built once per source hash with the SwiftSyntax that ships in Xcode.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    sources="$tree/src/Sources"
    mkdir -p "$sources/OpenSky/GameView" "$sources/OpenSkyX" "$sources/OpenSkyScripting" \
        "$sources/OpenSkyXAdapters"
    cat >"$sources/OpenSky/GameView/Probe.swift" <<'SWIFT'
// GameViewController in a comment, and DispatchSemaphore, match nothing.
extension GameViewController {}
let coordinator = MapCoordinator()
let text = "GameViewController"
SWIFT
    cat >"$sources/OpenSkyX/Probe.swift" <<'SWIFT'
import Dispatch
struct NodeWiring {}
final class Probe: @unchecked Sendable {
    var onFrameUpdate: (() -> Void)?
    func attach(world: ProbeWorld) {}
    func wireProbe() {}
    @discardableResult func run() -> String { "" }
    func cast() {
        let entry = PerkEntryPoint(rawValue: 3)
        let mask = shader.shaderFlags1 & 4
        let value = store.setting(editorID: "fProbe")
        let metal = renderer as? MetalRenderer
        Task.detached {}
        DispatchQueue.main.async {}
        let queue = DispatchQueue(label: "probe")
    }
}
SWIFT
    cat >"$sources/OpenSkyX/ProbeCoordinator.swift" <<'SWIFT'
public final class ProbeCoordinator {
    public var probeStore: ProbeStore
}
SWIFT
    cat >"$sources/OpenSkyX/ProbeCore.swift" <<'SWIFT'
let now = Date()
SWIFT
    cat >"$sources/OpenSkyScripting/PapyrusWorldProbeBridge.swift" <<'SWIFT'
let event = "OnProbe"
struct Bridge { let read: (Int) -> Int }
SWIFT
    printf 'final class Probe { unowned let owner: Probe }\n' \
        >"$sources/OpenSkyXAdapters/Probe.swift"
    expect_failure "$0" "$tree" "(game_view_controller_extension)" \
        "(coordinator_outside_session_scope)" "(controller_outside_composition_root)" \
        "(connection_step_type)" "(unchecked_sendable)" "(frame_callback_property)" \
        "(late_attached_world)" "(late_setter_method)" "(action_returns_text)" \
        "(perk_entry_point_literal)" "(shader_flag_mask)" "(game_setting_reader)" \
        "(renderer_downcast)" "(detached_task)" "(main_queue_or_semaphore)" \
        "(new_dispatch_queue)" "(late_setter_property)" "(pure_core_side_effect)" \
        "(papyrus_event_literal)" "(papyrus_loose_closure)" "(adapter_unowned_reference)"
fi

source_dir="$OPENSKY_TOOLS/syntax-lint"
shared="$(dirname "$(git -C "$OPENSKY_TOOLS" rev-parse --path-format=absolute --git-common-dir)")"
toolchain="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host"
hash="$( { swiftc --version 2>&1; cat "$source_dir"/*.swift; } | shasum | cut -c1-16)"
checker="$shared/.cache/syntax-lint/$hash/syntax-lint"
if [ ! -x "$checker" ]; then
    mkdir -p "$(dirname "$checker")"
    # The lint and its self-check run in parallel; each builds its own file, then renames it.
    swiftc -O -module-name SyntaxLint "$source_dir"/*.swift -o "$checker.$$" \
        -I "$toolchain" -L "$toolchain" -lSwiftSyntax -lSwiftParser \
        -Xlinker -rpath -Xlinker "$toolchain"
    mv "$checker.$$" "$checker"
fi

cd "$(git rev-parse --show-toplevel)"
files="$(checks_swift_files)"
[ -n "$files" ] || { echo "[ OK ] no changed Swift file to check"; exit 0; }
# shellcheck disable=SC2086 # one word per file
if ! "$checker" $files; then
    echo "[ERROR] a structural rule failed; each line names its rule and its reason" >&2
    exit 1
fi
echo "[ OK ] structural rules"
