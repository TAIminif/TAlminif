"""Validate the locally generated source archive without publishing it.

Run `moon package` first. `moon package --list` only lists candidate files and
must not be treated as evidence of a populated distributable archive.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "moon.mod", "README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "requirements-test.txt",
    "bin/moonc3d.mjs", "cmd/main/main.mbt", "cmd/main/moon.pkg", "lib/moon.pkg",
    "lib/file_codec.mbt", "lib/frame_codec.mbt", "lib/parameter_codec.mbt",
    "docs/FINAL_REVIEW.md", "scripts/review_regressions.py",
    "scripts/verify_consumer.py", "scripts/compatibility_cases.py", "scripts/check_package.py",
    "scripts/fixtures/source-consumer/main.mbt.template",
    "scripts/fixtures/source-consumer/moon.mod.template", "scripts/fixtures/source-consumer/moon.pkg.template",
}
EXCLUDED_PARTS = {".git", ".tools", ".codex", ".agents", ".mooncakes", "artifacts", "_build", "node_modules"}
EXCLUDED_NAMES = {".env", ".netrc", ".git-credentials"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="archive to inspect; defaults to this module/version's source package")
    parser.add_argument("--report", type=Path, default=ROOT / "artifacts" / "package-check.json")
    args = parser.parse_args()
    report = {"schema": "MoonC3D-package-check/1", "result": "running",
              "scope": "local source archive integrity and contents; no registry publication"}
    try:
        manifest = (ROOT / "moon.mod").read_text(encoding="utf-8")

        def value(key):
            match = re.search(r"(?m)^" + re.escape(key) + r'\s*=\s*"([^"\r\n]+)"\s*$', manifest)
            if not match:
                raise ValueError(f"Cannot read {key} from moon.mod")
            return match.group(1)

        module, version = value("name"), value("version")
        archive = args.archive or ROOT / "_build" / "publish" / f"{module.replace('/', '-')}-{version}.zip"
        archive = archive.resolve()
        report.update({"module": module, "version": version, "archive": archive.name})
        with zipfile.ZipFile(archive) as package:
            files = {item.filename.replace("\\", "/") for item in package.infolist() if not item.is_dir()}
            report["file_count"] = len(files)
            missing = sorted(REQUIRED - files)
            rejected = sorted(name for name in files if (
                PurePosixPath(name).is_absolute()
                or ".." in PurePosixPath(name).parts
                or set(PurePosixPath(name).parts) & EXCLUDED_PARTS
                or PurePosixPath(name).name in EXCLUDED_NAMES
            ))
            report["missing_required_files"] = missing
            report["excluded_files_found"] = rejected
            if missing or rejected:
                raise ValueError("Source archive has missing required files or excluded local state")
            corrupt = package.testzip()
            if corrupt is not None:
                raise ValueError("Archive CRC check failed: " + corrupt)
            if package.read("moon.mod") != (ROOT / "moon.mod").read_bytes():
                raise ValueError("Packaged module manifest differs from the working source")
        report["sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        report["result"] = "passed"
    except Exception as error:
        report["result"] = "failed"
        report["error"] = str(error)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"result": report["result"], "files": report.get("file_count", 0), "report": str(args.report)}))
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
