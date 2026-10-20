"""Reproduce the 0.2.1 fractional-rate and half-open time-crop regressions.

Build the JavaScript CLI first, then run with Python 3.11 or newer:
  moon build --target js --release
  python scripts/review_regressions.py

This standard-library-only suite never downloads data or imports MoonC3D
implementation code. It reuses compatibility_cases.WireReader, an independent
Python struct/VAX-F decoder, and compares every defined physical sample against
fixture equations. MoonC3D dump output is not a numerical oracle. py-c3d is not
used: its segmented-array and exact floating-rate-ratio restrictions are not
MoonC3D failures.

Each run creates artifacts/review-regressions-*/report.json. These new regression
cases are reported separately from the existing 21 compatibility cases and 54
transcoded outputs; this script does not update either historical total.
"""

from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys
import tempfile
import traceback

from compatibility_cases import PROCESSORS, ROOT, WireReader, cli, close, compare_document, sha256


RATES = (59.94, 29.97, 23.976)
SUBSAMPLES = (3, 10)
FRAME_COUNT = 30
POINT_COUNT = 2
ANALOG_COUNT = 3


def fixture(processor, rate, subsamples, floating):
    """Values encode frame/channel/sample identity and exact binary calibration."""
    channels = [
        {"label": "force", "description": "scaled force", "unit": "N", "scale": 0.25, "offset": -5},
        {"label": "voltage", "description": "scaled voltage", "unit": "V", "scale": 0.5, "offset": 7},
        {"label": "signal", "description": "scaled signal", "unit": "mV", "scale": 2.0, "offset": -11},
    ]
    frames = []
    for fi in range(FRAME_COUNT):
        points = []
        for pi in range(POINT_COUNT):
            valid = not (fi == 12 and pi == 1)
            points.append({
                "x": fi + pi * 0.25 if valid else 0,
                "y": -fi * 0.5 + pi * 1.25 if valid else 0,
                "z": fi * 0.25 - pi * 2.0 if valid else 0,
                "residual": ((fi + pi) % 8) * 0.25 if valid else -1,
                "cameras": (fi * 13 + pi * 31) % 128 if valid else 0,
                "valid": valid,
            })
        analog = []
        for ai, channel in enumerate(channels):
            analog.append([
                (fi * 19 + ai * 43 + si * 5 - 180 - channel["offset"])
                * channel["scale"] * 2.0
                for si in range(subsamples)
            ])
        frames.append({"number": fi + 1, "points": points, "analog": analog})
    return {
        "format": "MoonC3D/1", "processor": processor,
        "point_rate": rate, "scale": -0.25 if floating else 0.25,
        "first_frame": 1, "point_labels": ["index", "marker"],
        "point_descriptions": ["original zero-based frame index in X", "second marker"],
        "point_unit": "mm", "analog_subsamples": subsamples,
        "analog_global_scale": 2.0, "analog_unsigned": False,
        "analog_channels": channels, "frames": frames,
        # Events lie inside, rather than on, the crop boundaries. Their own
        # REAL*4 serialization must not be confused with frame-grid selection.
        "events": [{"time": time, "label": label} for time, label in
                   [(0.055, "before"), (0.075, "inside"), (0.095, "after")]],
    }


def write_fixture(folder, tag, source):
    json_path = folder / f"{tag}-source.json"
    path = folder / f"{tag}.c3d"
    json_path.write_text(json.dumps(source, indent=2), encoding="utf-8")
    cli("pack", json_path, path)
    return path


def verify_wire(path, expected):
    """Check metadata and all defined points/analog samples without CLI dump."""
    wire = WireReader(path.read_bytes())
    decoded = wire.document()
    compare_document(decoded, expected)
    # WireReader uses header subsamples to decode data. Separately require
    # ANALOG:RATE and the header's value count/rate to represent that same grid.
    close(wire.scalar("ANALOG", "RATE"),
          expected["point_rate"] * expected["analog_subsamples"],
          "ANALOG:RATE")
    close(wire.real(20), expected["point_rate"], "header point rate")
    assert wire.u16(4) == len(expected["analog_channels"]) * expected["analog_subsamples"], "header analog values/frame"
    assert wire.u16(18) == expected["analog_subsamples"], "header subsamples"
    assert wire.processor == expected["processor"], "processor encoding"
    return decoded


def case_metadata(name, processor, floating, source, path):
    return {
        "name": name, "processor": processor,
        "storage": "float32" if floating else "int16",
        "point_rate": source["point_rate"],
        "subsamples_per_frame": source["analog_subsamples"],
        "frames": len(source["frames"]), "points": POINT_COUNT,
        "analog_channels": ANALOG_COUNT,
        "defined_marker_samples_checked": sum(point["valid"] for frame in source["frames"] for point in frame["points"]),
        "analog_samples_checked": len(source["frames"]) * ANALOG_COUNT * source["analog_subsamples"],
        "file": path.name, "file_sha256": sha256(path.read_bytes()),
        "checks": ["independent wire decode", "all defined physical samples",
                   "labels, descriptions, units, calibration, events and frame numbers",
                   "header sample counts and parameter rates"],
    }


def fractional_case(folder, processor, rate, subsamples, floating):
    storage = "float32" if floating else "int16"
    name = f"fractional-{processor}-{str(rate).replace('.', 'p')}-{subsamples}-{storage}"
    source = fixture(processor, rate, subsamples, floating)
    path = write_fixture(folder, name, source)
    verify_wire(path, source)
    result = case_metadata(name, processor, floating, source, path)
    result["category"] = "fractional-rate"
    return result


def crop_case(folder, processor, floating, start, end, indices):
    storage = "float32" if floating else "int16"
    name = f"crop-{processor}-{storage}-{start:g}-{end:g}"
    source = fixture(processor, 100.0, 3, floating)
    path = write_fixture(folder, name + "-input", source)
    verify_wire(path, source)
    output = folder / f"{name}.c3d"
    cli("crop-time", path, output, start, end)
    wanted = {
        **source,
        "frames": [{**source["frames"][index], "number": i + 1}
                   for i, index in enumerate(indices)],
        "events": [{**event, "time": event["time"] - start}
                   for event in source["events"] if start <= event["time"] < end],
    }
    decoded = verify_wire(output, wanted)
    actual_indices = [frame["points"][0]["x"] for frame in decoded["frames"]]
    assert actual_indices == list(indices), ("selected original indices", actual_indices, indices)
    result = case_metadata(name, processor, floating, wanted, output)
    result.update({
        "category": "half-open-time-crop", "interval_seconds": [start, end],
        "interval_semantics": "start <= frame_start < end",
        "expected_original_indices": list(indices), "actual_original_indices": actual_indices,
        "input_file": path.name, "input_sha256": sha256(path.read_bytes()),
    })
    result["checks"].append("exact half-open decimal boundaries and rebased events")
    return result


def main():
    artifacts = ROOT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="review-regressions-", dir=artifacts))
    version_match = re.search(r'^version\s*=\s*"([^"]+)"',
                              (ROOT / "moon.mod").read_text(encoding="utf-8"), re.MULTILINE)
    report = {
        "schema": "MoonC3D-review-regressions/1",
        "library_version": version_match.group(1) if version_match else "unknown",
        "started_utc": datetime.now(timezone.utc).isoformat(), "artifacts": str(folder),
        "scope": {
            "fractional_rates": list(RATES), "subsamples_per_frame": list(SUBSAMPLES),
            "processors": list(PROCESSORS.values()), "storage": ["int16", "float32"],
            "fractional_rate_cases": 36, "half_open_crop_cases": 12,
            "crop_point_rate": 100.0, "crop_intervals_seconds": [[0.07, 0.09], [0.0, 0.07]],
            "existing_compatibility_totals": "unchanged: this is a separate regression suite",
        },
        "oracles": [
            "independent Python struct/VAX-F WireReader from scripts/compatibility_cases.py",
            "predefined frame/channel/sample equations and exact binary calibration",
            "explicit original frame-index lists for half-open time crops",
        ],
        "oracle_limitations": [
            "No MoonC3D dump output is used as a numerical oracle.",
            "py-c3d is not used; its segmented-array and exact fractional-rate-ratio limits are outside this oracle's scope.",
            "Invalid marker coordinates have no defined physical value; validity is checked and their coordinates are excluded.",
            "Numeric comparisons allow the documented REAL*4 storage precision; selected frame indices are checked exactly.",
        ],
        "prerequisites": ["Python 3.11+ without -O", "Node.js", "moon build --target js --release"],
        "cases": [], "failures": [], "result": "running",
    }

    def execute(name, operation):
        try:
            result = operation()
            result["result"] = "passed"
            report["cases"].append(result)
            print(f"PASS {name}", flush=True)
        except Exception as error:
            failure = {"name": name, "error": str(error), "traceback": traceback.format_exc()}
            report["failures"].append(failure)
            report["cases"].append({"name": name, "result": "failed", "error": str(error)})
            print(f"FAIL {name}: {error}", flush=True)

    try:
        if sys.version_info < (3, 11):
            raise RuntimeError("Python 3.11 or newer is required")
        if not __debug__:
            raise RuntimeError("Run without -O: the independent decoder uses assertions")
        compiled = ROOT / "_build" / "js" / "release" / "build" / "cmd" / "main" / "main.js"
        if not compiled.is_file():
            raise FileNotFoundError("Build missing: run moon build --target js --release first")
        report["compiled_cli_sha256"] = sha256(compiled.read_bytes())
        for processor in PROCESSORS.values():
            for floating in (False, True):
                for rate in RATES:
                    for subsamples in SUBSAMPLES:
                        execute(f"fractional {processor} {rate} Hz / {subsamples} {'float32' if floating else 'int16'}",
                                lambda p=processor, r=rate, s=subsamples, f=floating:
                                fractional_case(folder, p, r, s, f))
                for start, end, indices in [(0.07, 0.09, [7, 8]), (0.0, 0.07, list(range(7)))]:
                    execute(f"crop {processor} {'float32' if floating else 'int16'} [{start}, {end})",
                            lambda p=processor, f=floating, a=start, b=end, ix=indices:
                            crop_case(folder, p, f, a, b, ix))
    except Exception as error:
        report["failures"].append({"name": "suite prerequisites", "error": str(error),
                                   "traceback": traceback.format_exc()})

    report["passed_cases"] = sum(case["result"] == "passed" for case in report["cases"])
    report["result"] = "failed" if report["failures"] else "passed"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    report_path = folder / "report.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"result": report["result"], "passed_cases": report["passed_cases"],
                      "failures": len(report["failures"]), "report": str(report_path)}))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
