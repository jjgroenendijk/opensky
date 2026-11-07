"""Line and function coverage of the package modules from the last test run's profile.

It reads the profile with llvm-cov, because `xccov` reports no package files from a
bundle built with the compilation cache's prefix mapping.
"""

import pathlib
import subprocess
import sys

# Swift closures are functions to llvm-cov; a closure that never ran inside a tested
# function is a branch, so the line rule counts it and the function rule does not.
CLOSURE_MARKS = ("closure #", "implicit closure", "autoclosure")


def profile_objects(derived_data):
    """The newest profile and every package module binary of the Debug build."""
    build = pathlib.Path(derived_data) / "Build"
    profiles = sorted(
        build.glob("ProfileData/*/Coverage.profdata"), key=lambda path: path.stat().st_mtime
    )
    if not profiles:
        sys.exit(f"[FAIL] no coverage profile under {build}/ProfileData. Run: make test-unit COVERAGE=1")
    products = build / "Products/Debug"
    objects = [
        framework / framework.stem
        for framework in sorted((products / "PackageFrameworks").glob("OpenSky*.framework"))
        if (framework / framework.stem).exists()
    ] + sorted(products.glob("OpenSky*.o"))
    if not objects:
        sys.exit(f"[FAIL] no package modules under {products}. Run: make test-unit COVERAGE=1")
    return profiles[-1], objects


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
    """`Sources/...` for a profile path, which may carry the cache's `/^src/` prefix."""
    marker = name.find("Sources/")
    return name[marker:] if marker >= 0 else None


def parse_lcov(text):
    """{path: {"lines": {line: count}, "functions": [(line, name, count)]}} for Sources/."""
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
