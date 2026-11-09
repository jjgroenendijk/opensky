"""Line and function coverage of the package modules from the last test run's profile.

It reads the profile with llvm-cov, because `xccov` reports no package files from a
bundle built with the compilation cache's prefix mapping.
"""

import filecmp
import os
import pathlib
import subprocess
import sys
import tempfile

# Swift closures are functions to llvm-cov; a closure that never ran inside a tested
# function is a branch, so the line rule counts it and the function rule does not.
CLOSURE_MARKS = ("closure #", "implicit closure", "autoclosure")
# The compiler adds an init accessor to each property-wrapped stored property. It
# runs only when an init assigns the property, so a default value never calls it.
SYNTHESIZED_MARKS = ("property wrapped field init accessor",)


def current_profiles(newest, kept, sources_changed):
    """The newest profile, and each plan's kept profile no older than the sources."""
    return [newest] + [path for path, modified in kept if modified >= sources_changed]


def sources_changed():
    """When a file the package modules build from last changed."""
    files = [path for path in pathlib.Path("src/Sources").rglob("*") if path.is_file()]
    return max((path.stat().st_mtime for path in files + [pathlib.Path("src/Package.swift")]), default=0)


def merged_profile(build):
    """One profile over the newest run and every current kept run (`make test`)."""
    profiles = sorted(
        build.glob("ProfileData/*/Coverage.profdata"), key=lambda path: path.stat().st_mtime
    )
    if not profiles:
        sys.exit(f"[FAIL] no coverage profile under {build}/ProfileData. Run: make test COVERAGE=1")
    kept = [
        (path, path.stat().st_mtime)
        for path in sorted(build.glob("ProfileData/*.profdata"))
        if not filecmp.cmp(path, profiles[-1], shallow=False)
    ]
    chosen = current_profiles(profiles[-1], kept, sources_changed())
    if len(chosen) == 1:
        return chosen[0]
    merged = pathlib.Path(tempfile.gettempdir()) / f"opensky-coverage-{os.getpid()}.profdata"
    command = ["xcrun", "llvm-profdata", "merge", "-o", str(merged)] + [str(path) for path in chosen]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"[FAIL] llvm-profdata merge: {result.stderr.strip()[:400]}")
    print(f"[INFO] coverage merged from {len(chosen)} runs: " + ", ".join(p.name for p in chosen))
    return merged


def profile_objects(derived_data):
    """The merged profile and every package module binary of the Debug build."""
    build = pathlib.Path(derived_data) / "Build"
    profile = merged_profile(build)
    products = build / "Products/Debug"
    objects = [
        framework / framework.stem
        for framework in sorted((products / "PackageFrameworks").glob("OpenSky*.framework"))
        if (framework / framework.stem).exists()
    ] + sorted(products.glob("OpenSky*.o"))
    if not objects:
        sys.exit(f"[FAIL] no package modules under {products}. Run: make test COVERAGE=1")
    return profile, objects


def lcov(derived_data):
    """The profile as lcov text, over every package module binary."""
    profile, objects = profile_objects(derived_data)
    command = ["xcrun", "llvm-cov", "export", "-format=lcov", "-instr-profile", str(profile)]
    command.append(str(objects[0]))
    for extra in objects[1:]:
        command += ["-object", str(extra)]
    result = subprocess.run(command, capture_output=True, text=True)
    # A module without instrumented code (C headers only) fails alone; skip it.
    if result.returncode != 0 and not result.stdout:
        sys.exit(f"[FAIL] llvm-cov export: {result.stderr.strip()[:400]}")
    return result.stdout


def source_path(name):
    """`src/Sources/...` for a profile path, which may carry the cache's `/^src/` prefix."""
    marker = name.find("src/Sources/")
    return name[marker:] if marker >= 0 else None


def parse_lcov(text):
    """{path: {"lines": {line: count}, "functions": [(line, name, count)]}} for src/Sources/."""
    files, current, starts = {}, None, {}
    for raw in text.splitlines():
        key, _, value = raw.partition(":")
        if key == "SF":
            path = source_path(value)
            current = files.setdefault(path, {"lines": {}, "functions": []}) if path else None
            starts = {}
        elif current is None:
            continue
        elif key == "DA":
            line, count = value.split(",")[:2]
            current["lines"][int(line)] = current["lines"].get(int(line), 0) + int(count)
        elif key == "FN":
            line, name = value.split(",", 1)
            starts[name] = int(line)
        elif key == "FNDA":
            count, name = value.split(",", 1)
            current["functions"].append((starts.get(name, 0), name, int(count)))
    return files


def demangled(names):
    if not names:
        return []
    result = subprocess.run(
        ["xcrun", "swift-demangle", "--simplified"],
        input="\n".join(names),
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


def is_closure(readable):
    return any(mark in readable for mark in CLOSURE_MARKS)


def is_synthesized(readable):
    return any(mark in readable for mark in SYNTHESIZED_MARKS)
