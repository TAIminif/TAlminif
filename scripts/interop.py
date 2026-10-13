"""Independent numeric interoperability oracle: py-c3d 0.6.0, no source copying.

Run after installing requirements-test.txt. Generated fixtures stay in artifacts/.
Both input encoders and output decoders are independent of MoonC3D.
"""
import csv
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
import c3d
import numpy as np


def cli(*args, expected=0):
    result = subprocess.run(
        ["node", str(ROOT / "bin" / "moonc3d.mjs"), *map(str, args)],
        cwd=ROOT, env={**os.environ, "MOONC3D_NO_BUILD": "1"},
        capture_output=True, text=True, encoding="utf-8", timeout=30,
    )
    assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
    return json.loads(result.stdout if expected == 0 else result.stderr)


def oracle(path):
    with path.open("rb") as handle:
        reader = c3d.Reader(handle)
        frames = list(reader.read_frames(camera_sum=False))
        assert len(frames) == reader.last_frame - reader.first_frame + 1
        return {
            "first": reader.first_frame,
            "points": np.stack([x[1] for x in frames]),
            "analog": np.stack([x[2] for x in frames]),
            "labels": [x.rstrip() for x in reader.point_labels],
            "analog_labels": [x.rstrip() for x in reader.analog_labels],
            "custom": reader.get("CUSTOM:MATRIX").bytes,
            "point_rate": reader.point_rate,
            "analog_rate": reader.analog_rate,
        }


def fixture(path, scale):
    writer = c3d.Writer(point_rate=100, analog_rate=300, point_scale=scale, gen_scale=2.0)
    writer.set_start_frame(101)
    writer.set_point_labels(["Heel", "Toe", "Hip"])
    writer.set_analog_labels(["Force", "EMG"])
    writer.set_analog_scales([0.5, 0.25])
    writer.set_analog_offsets([10, -4])
    custom = writer.add_group(10, "CUSTOM", "independent test metadata")
    custom.add_array("MATRIX", "column-major payload", np.array([[1, -2], [300, -400]], dtype=np.int16))
    events = writer.add_group(20, "EVENT", "test events")
    events.add("USED", "count", 2, "<H", 2)
    events.add("TIMES", "minutes seconds", 4, "", struct.pack("<4f", 0, 1.035, 0, 1.095), 2, 2)
    events.add_str("LABELS", "event labels", "hit off ", 4, 2)
    frames = []
    for i in range(12):
        points = np.array([
            [i * 0.5, -i * 0.25, 10.0, 0.75, 3],
            [i + 2.0, 3.0, 4.0, -1.0 if 3 <= i < 6 else 0.25, 65],
            [100.0, i * 0.25, -8.0, 0.5, 127],
        ], dtype=np.float32)
        analog = np.array([[i * 3 + j for j in range(3)], [i * 0.5 + j * 0.5 for j in range(3)]], dtype=np.float64)
        frames.append((points, analog))
    writer.add_frames(frames)
    with path.open("wb") as handle:
        writer.write(handle)
    return oracle(path)


def compare_json(document, expected):
    assert document["first_frame"] == expected["first"]
    assert document["point_labels"] == expected["labels"]
    assert [x["label"] for x in document["analog_channels"]] == expected["analog_labels"]
    assert len(document["frames"]) == len(expected["points"])
    for i, frame in enumerate(document["frames"]):
        assert frame["number"] == expected["first"] + i
        for j, point in enumerate(frame["points"]):
            original = expected["points"][i, j]
            assert point["valid"] == (original[3] >= 0)
            if point["valid"]:
                np.testing.assert_allclose([point["x"], point["y"], point["z"], point["residual"]], original[:4], atol=1e-5, rtol=1e-6)
                assert point["cameras"] == original[4]
        np.testing.assert_allclose(frame["analog"], expected["analog"][i], atol=1e-5, rtol=1e-6)


def compare_files(actual, expected, indices=None, analog_indices=None, start=0, end=None):
    end = len(expected["points"]) if end is None else end
    indices = list(range(len(expected["labels"]))) if indices is None else indices
    analog_indices = list(range(len(expected["analog_labels"]))) if analog_indices is None else analog_indices
    points = expected["points"][start:end][:, indices]
    analog = expected["analog"][start:end][:, analog_indices]
    valid = points[:, :, 3] >= 0
    np.testing.assert_array_equal(actual["points"][:, :, 3] >= 0, valid)
    np.testing.assert_allclose(actual["points"][valid], points[valid], atol=1e-5, rtol=1e-6)
    np.testing.assert_allclose(actual["analog"], analog, atol=1e-5, rtol=1e-6)
    assert actual["labels"] == [expected["labels"][i] for i in indices]
    assert actual["analog_labels"] == [expected["analog_labels"][i] for i in analog_indices]
    assert actual["custom"] == expected["custom"]


def run():
    subprocess.run(["moon", "build", "--target", "js", "--release"], cwd=ROOT, check=True)
    (ROOT / "artifacts").mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="interop-", dir=ROOT / "artifacts"))
    checks = []
    for tag, scale in [("float", -0.25), ("integer", 0.25)]:
        source = folder / f"python-{tag}.c3d"
        expected = fixture(source, scale)
        interchange = folder / f"{tag}.json"
        cli("dump", source, interchange)
        document = json.loads(interchange.read_text(encoding="utf-8"))
        compare_json(document, expected)
        assert [e["label"] for e in document["events"]] == ["hit", "off"]
        assert cli("check", source)["ok"]
        repacked = folder / f"repacked-{tag}.c3d"
        cli("pack", interchange, repacked)
        compare_files(oracle(repacked), expected)
        cropped = folder / f"crop-{tag}.c3d"
        cli("crop", source, cropped, 3, 9)
        cropped_expected = oracle(cropped)
        assert cropped_expected["first"] == 1
        compare_files(cropped_expected, expected, start=3, end=9)
        crop_json = folder / f"crop-{tag}.json"
        cli("dump", cropped, crop_json)
        cropped_doc = json.loads(crop_json.read_text(encoding="utf-8"))
        assert len(cropped_doc["events"]) == 1
        np.testing.assert_allclose(cropped_doc["events"][0]["time"], 0.005, atol=1e-6)
        selected = folder / f"points-{tag}.c3d"
        cli("select-points", source, selected, "2,0")
        compare_files(oracle(selected), expected, indices=[2, 0])
        selected_analog = folder / f"analog-{tag}.c3d"
        cli("select-analog", source, selected_analog, "1")
        compare_files(oracle(selected_analog), expected, analog_indices=[1])
        converted = folder / f"converted-{tag}.c3d"
        cli("convert", source, converted, -scale)
        compare_files(oracle(converted), expected)
        statistics = cli("stats", source)
        assert statistics["markers"][1]["missing_samples"] == 3
        assert statistics["markers"][1]["longest_missing_run"] == 3
        for j, channel in enumerate(statistics["analog"]):
            values = expected["analog"][:, j].flatten()
            for name, value in [("mean", values.mean()), ("variance", values.var(ddof=1)), ("rms", np.sqrt(np.mean(values ** 2)))]:
                np.testing.assert_allclose(channel["samples"][name], value, atol=1e-8)
        for kind, rows in [("points", 36), ("analog", 72), ("events", 2)]:
            path = folder / f"{tag}-{kind}.csv"
            cli("csv", source, path, kind)
            with path.open(encoding="utf-8", newline="") as handle:
                records = list(csv.DictReader(handle))
            assert len(records) == rows
            if kind == "analog":
                np.testing.assert_allclose(float(records[2]["time"]), 1.0 + 1 / 300, atol=1e-8)
        checks.append(f"{tag}: decode, encode, crop, select, conversion, statistics, CSV")
    # Format failures must use structured diagnostics and leave no output behind.
    raw = (folder / "python-float.c3d").read_bytes()
    truncated = folder / "truncated.c3d"
    truncated.write_bytes(raw[:700])
    assert cli("check", truncated, expected=1)["error"] == "truncated"
    dec = folder / "unsupported.c3d"
    data = bytearray(raw)
    data[512 + 3] = 85
    dec.write_bytes(data)
    assert cli("inspect", dec, expected=1)["error"] == "unsupported"
    assert cli("pack", folder / "float.json", folder / "repacked-float.c3d", expected=2)["error"] == "HostIO"
    assert cli("select-points", folder / "python-float.c3d", folder / "bad-selection.c3d", "0,0", expected=1)["error"] == "invalid"
    assert not (folder / "bad-selection.c3d").exists()
    # The video header may describe a different range; parameter frames take priority.
    data = bytearray(raw)
    struct.pack_into("<HH", data, 6, 1, 1000)
    video = folder / "video-range.c3d"
    video.write_bytes(data)
    assert cli("inspect", video)["frames"] == 12
    checks.append("truncation, unsupported processor, overwrite refusal, invalid selection, video header range")
    report = {"oracle": "py-c3d 0.6.0", "checks": checks, "result": "passed", "artifacts": str(folder)}
    (folder / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    run()
