#!/usr/bin/env python3
"""Link the headless regression to existing macOS package build objects.

Usage: python3 scripts/run-legacy-fusion-check.py /tmp/powder-engine-build
Run the PowderEngine package build first. No vendored source is modified.
"""
from pathlib import Path
import subprocess
import sys
import tempfile


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout


root = Path(__file__).resolve().parent.parent
build = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/powder-engine-build")
bridge = root / "Native/Packages/PowderEngine/Sources/CBridge"
json_cpp = bridge.parent / "JsonCpp"
source = root / "scripts/check-legacy-fusion.cpp"
reference = root / "reference/The-Powder-Toy-100.1.400/src/simulation/elements/O2.cpp"

try:
    objects = []
    for target in ("CBridge", "JsonCpp"):
        lists = list(build.rglob(f"{target}.LinkFileList"))
        if len(lists) != 1:
            raise RuntimeError(f"Expected one {target}.LinkFileList in {build}, found {len(lists)}")
        objects.extend(Path(line) for line in lists[0].read_text().splitlines() if line)
    oxygen_objects = [path for path in objects if path.name == "O2.o"]
    if len(oxygen_objects) != 1:
        raise RuntimeError("Expected exactly one production O2 object")
    missing = [str(path) for path in objects if not path.is_file()]
    if missing:
        raise RuntimeError(f"Build objects missing: {missing}")
    common = ["xcrun", "clang++", "-std=c++20", "-mmacosx-version-min=14.0", "-g", "-O0"]
    for include in (bridge, bridge / "Upstream", bridge / "Generated", json_cpp / "include"):
        common.extend(["-I", str(include)])
    libraries = ["-lbz2", "-framework", "Accelerate"]
    with tempfile.TemporaryDirectory(prefix="powder-legacy-fusion-") as directory:
        temporary = Path(directory)
        production = temporary / "production-check"
        baseline = temporary / "reference-check"
        original_oxygen = temporary / "upstream-O2.o"
        run(common + [str(source)] + [str(path) for path in objects] + libraries + ["-o", str(production)])
        print(run([str(production)]), end="")
        run(common + ["-c", str(reference), "-o", str(original_oxygen)])
        reference_objects = [original_oxygen if path in oxygen_objects else path for path in objects]
        run(common + [str(source)] + [str(path) for path in reference_objects] + libraries + ["-o", str(baseline)])
        current = run([str(production), "--modern-fingerprint"]).strip()
        upstream = run([str(baseline), "--modern-fingerprint"]).strip()
        if current != upstream:
            raise RuntimeError(f"Modern O2 differs from unmodified pinned source: {current} != {upstream}")
        print(f"PASS pinned-source differential: modern O2 state/RNG fingerprint {current} matches unmodified v100.1.400 across 256 seeds")
except subprocess.CalledProcessError as error:
    print(error.stdout, end="", file=sys.stderr)
    print(error.stderr, end="", file=sys.stderr)
    raise SystemExit(error.returncode)
except Exception as error:
    print(f"FAIL {error}", file=sys.stderr)
    raise SystemExit(1)
