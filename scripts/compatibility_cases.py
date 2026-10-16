"""Reproduce MoonC3D's cross-encoding and >255-channel compatibility cases.

Build the JavaScript CLI first, install requirements-test.txt, then run:
  python scripts/compatibility_cases.py --download-official

The official archives are SHA-256 pinned and remain in ignored .tools/.
Generated files and the machine-readable report remain in ignored artifacts/.
This script never imports MoonC3D implementation code. Its small wire decoder
uses Python struct and the documented VAX F mathematical representation; it
checks generated output independently of MoonC3D's dump/pack round trip.
py-c3d 0.6.0 is an additional independent oracle for the official small files.
It is deliberately NOT used as the oracle for segmented analog metadata.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import traceback
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
PROCESSORS = {84: "intel", 85: "dec", 86: "mips"}
OFFICIAL = {
    "Sample01": {
        "url": "https://www.c3d.org/data/Sample01.zip",
        "sha256": "15f7277768d52a0a834c7fb96e07bdc916bfc076b6faf76e8b2654a04893308d",
    },
    "Sample02": {
        "url": "https://www.c3d.org/data/Sample02.zip",
        "sha256": "bf83f6197745ea1ced2a55cae9115b08816055d63c6d4463b53085a636f42a9b",
    },
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def cli(*args, expected=0):
    result = subprocess.run(
        ["node", str(ROOT / "bin" / "moonc3d.mjs"), *map(str, args)],
        cwd=ROOT,
        env={**os.environ, "MOONC3D_NO_BUILD": "1"},
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=90,
    )
    if result.returncode != expected:
        raise AssertionError(
            f"CLI {args!r} exited {result.returncode}: {result.stderr or result.stdout}"
        )
    return json.loads(result.stdout if expected == 0 else result.stderr)


def dump(path, folder, tag):
    output = folder / f"{tag}.json"
    cli("dump", path, output)
    return json.loads(output.read_text(encoding="utf-8"))


def close(actual, expected, label, atol=1e-5, rtol=1e-6):
    if not math.isclose(actual, expected, abs_tol=atol, rel_tol=rtol):
        raise AssertionError(f"{label}: {actual!r} != {expected!r}")


def compare_document(actual, expected):
    """Compare all physical samples; invalid coordinates have no defined value."""
    for key in ("first_frame", "point_labels", "point_descriptions", "point_unit",
                "analog_subsamples", "analog_unsigned", "processor"):
        if key in expected:
            assert actual[key] == expected[key], (key, actual[key], expected[key])
    for key in ("point_rate", "scale", "analog_global_scale"):
        if key in expected:
            close(actual[key], expected[key], key)
    assert len(actual["analog_channels"]) == len(expected["analog_channels"])
    for index, (got, wanted) in enumerate(zip(actual["analog_channels"], expected["analog_channels"])):
        for key in ("label", "description", "unit"):
            if key in wanted:
                assert got[key] == wanted[key], (index, key, got[key], wanted[key])
        for key in ("scale", "offset"):
            if key in wanted:
                close(got[key], wanted[key], f"channel {index} {key}")
    assert len(actual["frames"]) == len(expected["frames"])
    for fi, (got, wanted) in enumerate(zip(actual["frames"], expected["frames"])):
        assert got["number"] == wanted["number"], (fi, "frame number")
        assert len(got["points"]) == len(wanted["points"])
        for pi, (point, reference) in enumerate(zip(got["points"], wanted["points"])):
            assert point["valid"] == reference["valid"], (fi, pi, "valid")
            if reference["valid"]:
                for coordinate in ("x", "y", "z", "residual"):
                    close(point[coordinate], reference[coordinate], f"frame {fi} point {pi} {coordinate}")
                assert point["cameras"] == reference["cameras"], (fi, pi, "camera mask")
        assert len(got["analog"]) == len(wanted["analog"])
        for ai, (channel, reference) in enumerate(zip(got["analog"], wanted["analog"])):
            assert len(channel) == len(reference)
            for si, (sample, value) in enumerate(zip(channel, reference)):
                close(sample, value, f"frame {fi} analog {ai} sample {si}")
    if "events" in expected:
        assert len(actual["events"]) == len(expected["events"])
        for got, wanted in zip(actual["events"], expected["events"]):
            assert got["label"] == wanted["label"], (got, wanted)
            close(got["time"], wanted["time"], "event time")


class WireReader:
    """Test-only decoder, independent of the MoonBit reader and py-c3d."""

    def __init__(self, data):
        self.data = data
        self.parameter_start = (data[0] - 1) * 512
        self.processor_id = data[self.parameter_start + 3]
        self.processor = PROCESSORS[self.processor_id]
        self.endian = ">" if self.processor == "mips" else "<"
        groups, pending = {}, []
        position = self.parameter_start + 4
        limit = self.parameter_start + data[self.parameter_start + 2] * 512
        while position < limit:
            length, group = struct.unpack_from("bb", data, position)
            if not length or not group:
                break
            locked = length < 0
            name = data[position + 2:position + 2 + abs(length)].decode("ascii").upper()
            pointer = position + 2 + abs(length)
            jump = self.u16(pointer)
            cursor = pointer + 2
            if group < 0:
                groups[-group] = name
                payload_end = cursor + 1 + data[cursor]
            else:
                kind, rank = struct.unpack_from("bB", data, cursor)
                dimensions = list(data[cursor + 2:cursor + 2 + rank])
                count = math.prod(dimensions)
                start = cursor + 2 + rank
                payload = data[start:start + abs(kind) * count]
                assert len(payload) == abs(kind) * count
                pending.append((group, name, kind, dimensions, payload, locked))
                description_offset = start + len(payload)
                payload_end = description_offset + 1 + data[description_offset]
            assert payload_end <= limit
            if not jump:
                break
            assert jump >= 2 and position < pointer + jump <= limit, "invalid next-record pointer"
            position = pointer + jump
        self.parameters = {
            (groups[group], name): {"kind": kind, "dimensions": dimensions,
                                    "payload": payload, "locked": locked}
            for group, name, kind, dimensions, payload, locked in pending
        }

    def u16(self, position, data=None):
        return struct.unpack_from(self.endian + "H", self.data if data is None else data, position)[0]

    def i16(self, position, data=None):
        return struct.unpack_from(self.endian + "h", self.data if data is None else data, position)[0]

    def real(self, position, data=None):
        data = self.data if data is None else data
        if self.processor != "dec":
            return struct.unpack_from(self.endian + "f", data, position)[0]
        # VAX F words are little endian; the high fraction word comes first.
        first, second = struct.unpack_from("<HH", data, position)
        sign = first >> 15
        exponent = (first >> 7) & 255
        fraction = ((first & 127) << 16) | second
        if exponent == 0:
            assert sign == 0, "VAX reserved operand"
            return 0.0
        return (-1.0 if sign else 1.0) * math.ldexp(1.0 + fraction / 8388608.0, exponent - 129)

    def values(self, parameter, unsigned=False):
        kind, data = parameter["kind"], parameter["payload"]
        if kind == -1:
            width = parameter["dimensions"][0]
            if not width:
                return []
            return [data[i:i + width].rstrip(b" \0").decode("utf-8") for i in range(0, len(data), width)]
        if kind == 1:
            return list(struct.unpack(f"{len(data)}b", data))
        if kind == 2:
            read = self.u16 if unsigned else self.i16
            return [read(i, data) for i in range(0, len(data), 2)]
        assert kind == 4
        return [self.real(i, data) for i in range(0, len(data), 4)]

    def scalar(self, group, name, default=None, unsigned=False):
        parameter = self.parameters.get((group, name))
        return default if parameter is None else self.values(parameter, unsigned=unsigned)[0]

    def series(self, group, base, count, default=None, unsigned=False):
        values, segment = [], 1
        while True:
            name = base if segment == 1 else base + str(segment)
            parameter = self.parameters.get((group, name))
            if parameter is None:
                break
            values.extend(self.values(parameter, unsigned=unsigned))
            segment += 1
        if len(values) < count:
            assert default is not None, (group, base, count, len(values))
            values.extend([default] * (count - len(values)))
        return values[:count]

    def document(self):
        points = int(self.scalar("POINT", "USED", self.u16(2), unsigned=True))
        channels = int(self.scalar("ANALOG", "USED", 0, unsigned=True))
        scale = self.scalar("POINT", "SCALE", self.real(12))
        rate = self.scalar("POINT", "RATE", self.real(20))
        frame_count = int(self.scalar("POINT", "FRAMES", self.u16(8) - self.u16(6) + 1, unsigned=True))
        first = self.u16(6)
        if ("TRIAL", "ACTUAL_START_FIELD") in self.parameters:
            words = self.values(self.parameters[("TRIAL", "ACTUAL_START_FIELD")], unsigned=True)
            first = words[0] + (words[1] << 16)
        subsamples = self.u16(18) if channels else 0
        global_scale = self.scalar("ANALOG", "GEN_SCALE", 1.0)
        unsigned = self.scalar("ANALOG", "FORMAT", "SIGNED").upper() == "UNSIGNED"
        labels = self.series("POINT", "LABELS", points, default="")
        descriptions = self.series("POINT", "DESCRIPTIONS", points, default="")
        analog_labels = self.series("ANALOG", "LABELS", channels, default="")
        analog_descriptions = self.series("ANALOG", "DESCRIPTIONS", channels, default="")
        units = self.series("ANALOG", "UNITS", channels, default="")
        scales = self.series("ANALOG", "SCALE", channels, default=1.0)
        offsets = self.series("ANALOG", "OFFSET", channels, default=0, unsigned=unsigned)
        cursor = (int(self.scalar("POINT", "DATA_START", self.u16(16), unsigned=True)) - 1) * 512
        frames = []
        for fi in range(frame_count):
            markers = []
            for _ in range(points):
                if scale < 0:
                    x, y, z, packed = (self.real(cursor + i * 4) for i in range(4))
                    assert packed.is_integer()
                    packed = int(packed)
                    cursor += 16
                else:
                    raw = struct.unpack_from(self.endian + "hhhh", self.data, cursor)
                    x, y, z = (v * scale for v in raw[:3])
                    packed = raw[3]
                    cursor += 8
                valid = packed >= 0
                markers.append({"x": x, "y": y, "z": z, "valid": valid,
                                "residual": (packed & 255) * abs(scale) if valid else -1.0,
                                "cameras": (packed >> 8) & 127 if valid else 0})
            analog = [[] for _ in range(channels)]
            for _ in range(subsamples):
                for ai in range(channels):
                    if scale < 0:
                        raw = self.real(cursor)
                        cursor += 4
                    else:
                        raw = self.u16(cursor) if unsigned else self.i16(cursor)
                        cursor += 2
                    analog[ai].append((raw - offsets[ai]) * scales[ai] * global_scale)
            frames.append({"number": first + fi, "points": markers, "analog": analog})
        events = []
        count = self.scalar("EVENT", "USED", None, unsigned=True)
        if count is not None:
            count = int(count)
            if count:
                times = self.values(self.parameters[("EVENT", "TIMES")])
                event_labels = self.series("EVENT", "LABELS", count, default="")
                events = [{"time": times[2 * i] * 60 + times[2 * i + 1], "label": event_labels[i]} for i in range(count)]
        else:
            for i in range(self.u16(300)):
                events.append({"time": self.real(304 + i * 4),
                               "label": self.data[396 + i * 4:400 + i * 4].rstrip(b" \0").decode("ascii")})
        return {
            "processor": self.processor, "first_frame": first, "point_labels": labels,
            "point_descriptions": descriptions, "point_unit": self.scalar("POINT", "UNITS", "mm"),
            "point_rate": rate, "scale": scale, "analog_subsamples": subsamples,
            "analog_global_scale": global_scale, "analog_unsigned": unsigned,
            "analog_channels": [{"label": analog_labels[i], "description": analog_descriptions[i],
                                 "unit": units[i], "scale": scales[i], "offset": offsets[i]} for i in range(channels)],
            "frames": frames, "events": events,
        }


def synthetic_document(processor, floating, unsigned=False):
    count, first, subsamples = 511, 101, 3
    scales = [0.25, 0.5, 1.0, 2.0]
    channels = [
        {"label": f"A{i:03}", "description": f"analog {i:03}", "unit": "N" if i % 2 == 0 else "mV",
         "scale": scales[i % 4], "offset": 45000 + i if unsigned else i - 250}
        for i in range(count)
    ]
    frames = []
    for fi in range(3):
        points = []
        for pi in range(count):
            valid = not (fi == 1 and pi == 255)
            points.append({"x": (pi - 255) * 0.25 + fi * 0.5 if valid else 0,
                           "y": (pi % 19 - 9) * 0.5 - fi * 0.25 if valid else 0,
                           "z": (pi % 13) * 1.25 + fi * 0.25 if valid else 0,
                           "residual": (pi % 8) * 0.25 if valid else -1,
                           "cameras": (pi * 13) % 128 if valid else 0, "valid": valid})
        analog = []
        for ai, channel in enumerate(channels):
            raw_start = 40000 + ai % 31 if unsigned else ai % 31 - 15
            analog.append([(raw_start + fi * 11 + si * 3 - channel["offset"]) * channel["scale"] * 2 for si in range(subsamples)])
        frames.append({"number": first + fi, "points": points, "analog": analog})
    raw_parameters = [
        ("MATRIX", 2, [2, 2], struct.pack("<4h", 1, -2, 300, -400)),
        ("REALS", 4, [3], struct.pack("<3f", 0.125, -8192, 3.5)),
        ("BYTES", 1, [4], bytes([128, 255, 0, 127])),
        ("NOTE", -1, [10], b"test case "),
    ]
    return {
        "format": "MoonC3D/1", "processor": processor, "point_rate": 100,
        "scale": -0.25 if floating else 0.25, "first_frame": first,
        "point_labels": [f"P{i:03}" for i in range(count)],
        "point_descriptions": [f"marker {i:03}" for i in range(count)], "point_unit": "mm",
        "analog_subsamples": subsamples, "analog_global_scale": 2, "analog_unsigned": unsigned,
        "analog_channels": channels, "frames": frames,
        "events": [{"time": 1.005, "label": "first"}, {"time": 1.025, "label": "last"}],
        "parameters": {
            "groups": [{"id": 10, "name": "CUSTOM", "description_hex": "", "locked": False}],
            "values": [{"processor": "intel", "group_id": 10, "name": name, "data_type": kind,
                        "dimensions": dimensions, "data_hex": payload.hex(), "description_hex": "", "locked": False}
                       for name, kind, dimensions, payload in raw_parameters],
        },
    }


def assert_custom(wire):
    for name, expected in [("MATRIX", [1, -2, 300, -400]), ("REALS", [0.125, -8192, 3.5]),
                           ("BYTES", [-128, -1, 0, 127]), ("NOTE", ["test case"])]:
        assert wire.values(wire.parameters[("CUSTOM", name)]) == expected, name


def assert_segments(wire, point_count=511, analog_count=511):
    for group, bases, count in [
        ("POINT", ("LABELS", "DESCRIPTIONS"), point_count),
        ("ANALOG", ("LABELS", "DESCRIPTIONS", "UNITS", "SCALE", "OFFSET"), analog_count),
    ]:
        lengths = [min(255, count - start) for start in range(0, count, 255)]
        for base in bases:
            for index, length in enumerate(lengths, 1):
                name = base if index == 1 else base + str(index)
                parameter = wire.parameters[(group, name)]
                assert len(wire.values(parameter)) == length, (group, name, length)
            stale = base + str(len(lengths) + 1)
            assert (group, stale) not in wire.parameters, ("stale segment", group, stale)


def synthetic_case(folder, processor, floating, unsigned):
    tag = f"synthetic-{processor}-{'float' if floating else 'integer'}{'-unsigned' if unsigned else ''}"
    source = synthetic_document(processor, floating, unsigned)
    json_path, path = folder / f"{tag}-source.json", folder / f"{tag}.c3d"
    json_path.write_text(json.dumps(source), encoding="utf-8")
    cli("pack", json_path, path)
    wire = WireReader(path.read_bytes())
    compare_document(wire.document(), source)
    assert_custom(wire)
    assert_segments(wire)
    actual = dump(path, folder, f"{tag}-dump")
    compare_document(actual, source)
    assert cli("check", path)["ok"]
    checks = ["independent wire decode", "semantic JSON", "LABELS2/LABELS3 and numeric segments", "custom typed parameters"]
    for target in PROCESSORS.values():
        if target == processor:
            continue
        converted = folder / f"{tag}-to-{target}.c3d"
        cli("convert-encoding", path, converted, target)
        wanted = {**source, "processor": target}
        reader = WireReader(converted.read_bytes())
        compare_document(reader.document(), wanted)
        assert_custom(reader)
        assert_segments(reader)
        compare_document(dump(converted, folder, f"{tag}-to-{target}-dump"), wanted)
    checks.append("conversion to both other processor encodings")
    # Cross both 255-entry boundaries, then ensure surplus numbered metadata is removed.
    indices = [510, 255, 254, 0]
    point_selected = folder / f"{tag}-points.c3d"
    cli("select-points", path, point_selected, ",".join(map(str, indices)))
    point_wanted = {**source, "point_labels": [source["point_labels"][i] for i in indices],
                    "point_descriptions": [source["point_descriptions"][i] for i in indices],
                    "frames": [{**frame, "points": [frame["points"][i] for i in indices]} for frame in source["frames"]]}
    reader = WireReader(point_selected.read_bytes())
    compare_document(reader.document(), point_wanted)
    assert_segments(reader, point_count=4)
    analog_selected = folder / f"{tag}-analog.c3d"
    cli("select-analog", path, analog_selected, ",".join(map(str, indices)))
    analog_wanted = {**source, "analog_channels": [source["analog_channels"][i] for i in indices],
                     "frames": [{**frame, "analog": [frame["analog"][i] for i in indices]} for frame in source["frames"]]}
    reader = WireReader(analog_selected.read_bytes())
    compare_document(reader.document(), analog_wanted)
    assert_segments(reader, analog_count=4)
    cropped = folder / f"{tag}-crop.c3d"
    cli("crop", path, cropped, 1, 3)
    crop_wanted = {**source, "first_frame": 1,
                   "frames": [{**frame, "number": i + 1} for i, frame in enumerate(source["frames"][1:])],
                   "events": [{"label": "last", "time": 0.015}]}
    compare_document(WireReader(cropped.read_bytes()).document(), crop_wanted)
    checks.extend(["point/analog selection at indices 254,255,510", "stale segment removal", "crop and event rebase"])
    return {"name": tag, "processor": processor, "storage": "float32" if floating else "int16",
            "unsigned_analog": unsigned, "points": 511, "analog_channels": 511,
            "subsamples_per_frame": 3, "frames": 3, "checks": checks,
            "file_sha256": sha256(path.read_bytes()), "result": "passed"}


def official_archive(name, cache, allow_download):
    specification = OFFICIAL[name]
    archive = cache / f"{name}.zip"
    if not archive.exists():
        if not allow_download:
            raise FileNotFoundError(f"Missing {archive}; rerun with --download-official")
        with urllib.request.urlopen(specification["url"], timeout=60) as response:
            payload = response.read(8 * 1024 * 1024 + 1)
        assert len(payload) <= 8 * 1024 * 1024, "unexpected official archive size"
        assert sha256(payload) == specification["sha256"], f"{name} archive hash changed"
        cache.mkdir(parents=True, exist_ok=True)
        archive.write_bytes(payload)
    assert sha256(archive.read_bytes()) == specification["sha256"], f"{name} cached archive hash mismatch"
    return archive


def python_oracle(data):
    import c3d  # Pinned in requirements-test.txt; no implementation copied.

    assert c3d.__version__ == "0.6.0", f"Install pinned py-c3d 0.6.0, found {c3d.__version__}"
    reader = c3d.Reader(io.BytesIO(data))
    frames = []
    for number, points, analog in reader.read_frames(camera_sum=False):
        frames.append({"number": int(number),
                       "points": [{"x": float(p[0]), "y": float(p[1]), "z": float(p[2]),
                                   "residual": float(p[3]), "valid": bool(p[3] >= 0), "cameras": int(p[4])} for p in points],
                       "analog": analog.tolist()})
    assert len(frames) == reader.last_frame - reader.first_frame + 1
    event_used = reader.get("EVENT:USED")
    if event_used is not None:
        event_count = int(event_used.uint16_value)
        if event_count:
            times = reader.get("EVENT:TIMES").float_array.reshape((-1, 2))
            labels = reader.get("EVENT:LABELS").string_array
            events = [{"time": float(times[i, 0] * 60 + times[i, 1]), "label": labels[i].rstrip()} for i in range(event_count)]
        else:
            events = []
    else:
        events = [{"time": float(time), "label": label.rstrip()} for time, label in reader.header.events]
    return {"first_frame": int(reader.first_frame), "point_rate": float(reader.point_rate),
            "scale": float(reader.point_scale), "point_labels": [label.rstrip() for label in reader.point_labels[:reader.point_used]],
            "analog_channels": [{"label": label.rstrip()} for label in reader.analog_labels[:reader.analog_used]],
            "frames": frames,
            "events": events}


def official_cases(name, archive, folder):
    results = []
    extraction = folder / name
    extraction.mkdir()
    with zipfile.ZipFile(archive) as zipped:
        readmes = [member for member in zipped.namelist() if member.lower().endswith(".txt")]
        for member in readmes:
            (extraction / Path(member).name).write_bytes(zipped.read(member))
        members = sorted(member for member in zipped.namelist() if member.lower().endswith(".c3d"))
        assert len(members) == 6, (name, members)
        combinations = set()
        for member in members:
            original = zipped.read(member)
            path = extraction / Path(member).name
            path.write_bytes(original)
            validation_status = "original"
            repair = None
            raw = original
            if name == "Sample02" and path.name in ("sgi_int.c3d", "sgi_real.c3d"):
                # These two published files have one malformed final pointer:
                # all prior pointers are big endian, but this field is 3f01.
                # Test rejection of the unmodified file first, then keep an
                # explicitly named local repair. Never modify the pinned ZIP.
                assert original[5429:5431] == b"\x3f\x01"
                assert cli("check", path, expected=1)["error"] == "invalid"
                patched = bytearray(original)
                struct.pack_into(">H", patched, 5429, 319)
                raw = bytes(patched)
                path = path.with_name(path.stem + "-repaired.c3d")
                path.write_bytes(raw)
                repair = {
                    "reason": "final POINT:LABELS next-record offset stored in wrong byte order",
                    "byte_offset_zero_based": 5429,
                    "original_bytes_hex": "3f01",
                    "repaired_bytes_hex": "013f",
                    "numeric_jump": 319,
                    "original_sha256": sha256(original),
                    "repaired_sha256": sha256(raw),
                    "original_validation": "expected structured invalid rejection",
                }
                (extraction / (path.stem + "-provenance.json")).write_text(
                    json.dumps(repair, indent=2), encoding="utf-8")
                validation_status = "repaired copy; original intentionally rejected"
            wire = WireReader(raw)
            expected = python_oracle(original)
            if repair:
                compare_document(python_oracle(raw), expected)
            expected["processor"] = wire.processor
            expected["point_labels"] = expected["point_labels"][:len(expected["frames"][0]["points"])]
            expected["analog_channels"] = expected["analog_channels"][:len(expected["frames"][0]["analog"])]
            tag = f"{name}-{path.stem}"
            actual = dump(path, folder, tag)
            compare_document(actual, expected)
            assert cli("check", path)["ok"]
            storage = "float32" if expected["scale"] < 0 else "int16"
            combinations.add((wire.processor, storage))
            for target in PROCESSORS.values():
                output = extraction / f"{path.stem}-to-{target}.c3d"
                cli("convert-encoding", path, output, target)
                converted = python_oracle(output.read_bytes())
                converted["processor"] = WireReader(output.read_bytes()).processor
                compare_document(converted, {**expected, "processor": target})
            results.append({"name": tag, "processor": wire.processor, "storage": storage,
                            "points": len(expected["frames"][0]["points"]),
                            "analog_channels": len(expected["frames"][0]["analog"]),
                            "frames": len(expected["frames"]), "header_events": len(expected["events"]),
                            "sha256": sha256(original), "tested_sha256": sha256(raw), "source_archive": name,
                            "validation_status": validation_status, "repair": repair,
                            "checks": ["every physical sample versus py-c3d 0.6.0", "legacy header events",
                                       "all three output encodings decoded independently by py-c3d"],
                            "result": "passed"})
        assert combinations == {(processor, storage) for processor in PROCESSORS.values() for storage in ("int16", "float32")}
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download-official", action="store_true", help="download missing SHA-256 pinned official archives")
    parser.add_argument("--skip-official", action="store_true", help="run only generated cases; report explicitly records the reduced scope")
    parser.add_argument("--output", type=Path, help="new output directory (default: unique artifacts/compatibility-* directory)")
    args = parser.parse_args()
    artifacts = ROOT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    if args.output:
        folder = args.output.resolve()
        folder.mkdir(parents=True, exist_ok=False)
    else:
        folder = Path(tempfile.mkdtemp(prefix="compatibility-", dir=artifacts))
    report = {"schema": "MoonC3D-compatibility/1", "started_utc": datetime.now(timezone.utc).isoformat(),
              "artifacts": str(folder), "oracles": ["independent Python wire decoder", "synthetic physical-value equations"],
              "official_sources": OFFICIAL, "cases": [], "failures": [], "result": "running"}
    if not args.skip_official:
        report["oracles"].append("py-c3d 0.6.0 (official files only; not used for segmented arrays)")

    def execute(name, operation):
        try:
            result = operation()
            report["cases"].extend(result if isinstance(result, list) else [result])
            print(f"PASS {name}", flush=True)
        except Exception as error:
            report["failures"].append({"name": name, "error": str(error), "traceback": traceback.format_exc()})
            print(f"FAIL {name}: {error}", flush=True)

    for processor in PROCESSORS.values():
        for floating, unsigned in [(False, False), (True, False), (False, True)]:
            execute(f"synthetic {processor} {'float' if floating else 'integer'} unsigned={unsigned}",
                    lambda p=processor, f=floating, u=unsigned: synthetic_case(folder, p, f, u))
    if args.skip_official:
        report["official_status"] = "skipped by explicit --skip-official option"
    else:
        cache = ROOT / ".tools" / "compatibility"
        for name in OFFICIAL:
            execute(name, lambda n=name: official_cases(n, official_archive(n, cache, args.download_official), folder))
        report["official_status"] = "failed" if any(failure["name"] in OFFICIAL for failure in report["failures"]) else "passed"
    report["result"] = "failed" if report["failures"] else "passed"
    report["official_original_cases"] = sum(case.get("validation_status") == "original" for case in report["cases"])
    report["official_repaired_cases"] = sum(bool(case.get("repair")) for case in report["cases"])
    report["fixture_notes"] = [
        "Sample02 SGI integer and real originals contain a malformed final next-record offset. They must be rejected; only explicitly repaired local copies undergo numeric tests.",
        "Sample02 DEC integer contains 8 header events, while its other five variants contain 9; each file is compared with its own independent oracle.",
    ]
    report["scope"] = "generated cases only" if args.skip_official else "generated and official cases"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    (folder / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"result": report["result"], "scope": report["scope"], "passed_cases": len(report["cases"]),
                      "failed_groups": len(report["failures"]), "report": str(folder / "report.json")}, ensure_ascii=False))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
