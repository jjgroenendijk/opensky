#!/bin/sh
# Writes the stubs of a new top-level openskycli command, so every place that
# tools/lint/cli-conventions.sh checks has an entry from the start.
#
# Usage: tools/new-cli-command.sh NAME GROUP
#   NAME   the command name in kebab case, such as `light-probe`.
#   GROUP  the help group: "Game data", "World", "Game rules", "Assets",
#          "Rendering", or "The app".
#
# Each stub says TODO; `make cli-conventions` fails until every TODO is replaced.
set -eu

cd "$(git rev-parse --show-toplevel)"

name="${1:-}"
group="${2:-}"
if ! printf '%s\n' "$name" | grep -qE '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'; then
  echo "[ERROR] NAME must be kebab case, such as light-probe" >&2
  exit 2
fi
case "$group" in
  "Game data" | "World" | "Game rules" | "Assets" | "Rendering" | "The app") ;;
  *)
    echo "[ERROR] GROUP must be one of: Game data, World, Game rules, Assets, Rendering, The app" >&2
    exit 2
    ;;
esac

type="$(printf '%s\n' "$name" | awk -F- '{ for (i = 1; i <= NF; i++) printf "%s", toupper(substr($i, 1, 1)) substr($i, 2) }')"
arguments="Sources/OpenSkyCLIArguments/${type}Arguments.swift"
command="Sources/OpenSkyCLI/Commands/${type}Command.swift"
tree=Sources/OpenSkyCLIArguments/OpenSkyCommandLine.swift

for file in "$arguments" "$command"; do
  [ ! -e "$file" ] || { echo "[ERROR] $file already exists" >&2; exit 1; }
done
grep -q "CommandGroup(name: \"$group\"" "$tree" \
  || { echo "[ERROR] no help group \"$group\" in $tree" >&2; exit 1; }

cat >"$arguments" <<EOF
import ArgumentParser

public struct ${type}Arguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "$name",
        abstract: "TODO: say what $name checks."
    )
    @OptionGroup public var global: GlobalOptions

    public init() {}
}
EOF

cat >"$command" <<EOF
// \`$name\`: TODO: say what it reads and what its output proves.

import OpenSkyCLIArguments

enum ${type}Command {
    static func run(context _: CLIContext, arguments _: ${type}Arguments) throws {
        print("[INFO] $name: TODO")
    }
}
EOF

cat >>Sources/OpenSkyCLI/CommandRunners.swift <<EOF

extension ${type}Arguments: CLIRunnable {
    func execute() throws {
        try ${type}Command.run(context: context(), arguments: self)
    }
}
EOF

# The new type goes first in its help group.
awk -v group="$group" -v type="$type" '
  { print }
  index($0, "CommandGroup(name: \"" group "\"") { print "                " type "Arguments.self," }
' "$tree" >"$tree.new" && mv "$tree.new" "$tree"

# The docs row goes first in the table of the section named like the group.
awk -v group="$group" -v name="$name" '
  { print }
  $0 == "### " group { section = 1 }
  section && /^\| --- \| --- \|$/ { print "| `" name "` | TODO: what it checks |"; section = 0 }
' docs/tools/cli.md >docs/tools/cli.md.new && mv docs/tools/cli.md.new docs/tools/cli.md

awk -v name="$name" '
  /^echo "\[INFO\] probe passed/ { print "run \"" name " (TODO: what the run proves)\" " name "\n" }
  { print }
' tools/probe.sh >tools/probe.sh.new && mv tools/probe.sh.new tools/probe.sh
chmod +x tools/probe.sh

echo "[INFO] wrote $arguments and $command"
echo "[INFO] added a runner, a help group entry, a docs/tools/cli.md row, and a tools/probe.sh run"
echo "[INFO] replace every TODO, then run make fix and make cli-conventions"
