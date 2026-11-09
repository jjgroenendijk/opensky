# shellcheck shell=sh
# Where builds go, for make and for a script run on its own. Sourced, never run.
# Every checkout's build tree sits in the main checkout's hidden .cache/Build, on
# the data volume, and every tree shares one compilation cache store and one set
# of SDK modules (docs/tools/build-system.md). CI sets the variables itself.
opensky_root="$(git rev-parse --show-toplevel)"
opensky_shared="$(dirname "$(git -C "$opensky_root" rev-parse --path-format=absolute --git-common-dir)")"
: "${OPENSKY_DERIVED_DATA:=$opensky_shared/.cache/Build/$(basename "$opensky_root")}"
: "${OPENSKY_COMPILATION_CACHE:=$opensky_shared/.cache/CompilationCache.noindex}"
: "${OPENSKY_SDK_MODULES:=$opensky_shared/.cache/SDKModules.noindex}"
# Settings that must reach the package targets too; xcodebuild reads this variable.
: "${XCODE_XCCONFIG_FILE:=$opensky_root/src/config/Build/Overrides.xcconfig}"
export OPENSKY_DERIVED_DATA OPENSKY_COMPILATION_CACHE OPENSKY_SDK_MODULES XCODE_XCCONFIG_FILE
