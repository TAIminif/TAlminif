"""Check MoonC3D's public API from a separate source-dependent MoonBit module.

Run: python scripts/verify_consumer.py
Requires MoonBit; no registry login, publication or Python test dependencies.
The tracked templates are copied into a unique ignored artifacts/ workspace.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "scripts" / "fixtures" / "source-consumer"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("js", "wasm-gc", "wasm", "native"), default="js")
    args = parser.parse_args()
    artifacts = ROOT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="source-consumer-", dir=artifacts))
    report = {
        "schema": "MoonC3D-source-consumer/1",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "result": "running",
        "target": args.target,
        "scope": "separate module importing the public library through moon.work",
        "processors": ["intel", "dec", "mips"],
        "point_rate_hz": 59.94,
        "analog_subsamples": 3,
        "commands": [],
    }
    try:
        manifest = (ROOT / "moon.mod").read_text(encoding="utf-8")

        def value(key):
            match = re.search(r"(?m)^" + re.escape(key) + r'\s*=\s*"([^"\r\n]+)"\s*$', manifest)
            if not match:
                raise ValueError(f"Cannot read {key} from moon.mod")
            return match.group(1)

        module, version = value("name"), value("version")
        report["module"] = module
        report["version"] = version
        for source in sorted(FIXTURES.glob("*.template")):
            text = source.read_text(encoding="utf-8")
            text = text.replace("@MODULE@", module).replace("@VERSION@", version)
            (folder / source.name.removesuffix(".template")).write_text(text, encoding="utf-8")
        if not all((folder / name).is_file() for name in ("main.mbt", "moon.mod", "moon.pkg")):
            raise ValueError("Consumer fixture is incomplete")
        root_member = Path(os.path.relpath(ROOT, folder)).as_posix()
        (folder / "moon.work").write_text(
            "members = " + json.dumps([".", root_member]) + "\n", encoding="utf-8",
        )
        env = os.environ.copy()
        executable = "moon.exe" if os.name == "nt" else "moon"
        configured = env.get("MOONC3D_MOON_HOME")
        isolated = ROOT / ".tools" / "moon-20261012"
        home = Path(configured) if configured else isolated if (isolated / "bin" / executable).is_file() else None
        if home is not None:
            home = home.resolve()
            moon = str(home / "bin" / executable)
            env["MOON_HOME"] = str(home)
            env["PATH"] = str(home / "bin") + os.pathsep + env.get("PATH", "")
        else:
            moon = shutil.which(executable)
            if not moon:
                raise ValueError("MoonBit is required; install it or set MOONC3D_MOON_HOME")
        commands = [
            [moon, "check", "--target", args.target, "--deny-warn"],
            [moon, "run", "--target", args.target, "."],
        ]
        for command in commands:
            completed = subprocess.run(
                command, cwd=folder, env=env, capture_output=True, text=True,
                encoding="utf-8", timeout=180,
            )
            report["commands"].append({
                "args": command[1:], "exit_code": completed.returncode,
                "stdout": completed.stdout, "stderr": completed.stderr,
            })
            if completed.returncode:
                raise RuntimeError(f"Consumer {' '.join(command[1:])} failed")
        output = report["commands"][-1]["stdout"]
        if "MoonC3D external consumer PASS" not in output:
            raise RuntimeError("Consumer completed without its success marker")
        report["result"] = "passed"
    except Exception as error:
        report["result"] = "failed"
        report["error"] = str(error)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    result_path = folder / "result.json"
    result_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"result": report["result"], "target": args.target, "report": str(result_path)}))
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
