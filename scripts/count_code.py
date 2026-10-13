"""Count physical MoonBit lines excluding generated files, comments and blanks.

Production, examples and tests are separate. This repository metric does not
claim to establish an organizer's assessment of effective contributions.
"""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
totals = {"production": 0, "tests": 0, "examples": 0}
files = []
for directory in ("lib", "cmd", "examples"):
    for path in sorted((root / directory).rglob("*.mbt")):
        if "generated" in path.name:
            continue
        category = "examples" if directory == "examples" else "tests" if path.name.endswith("_test.mbt") else "production"
        lines = sum(bool(line.strip()) and not line.lstrip().startswith("//") for line in path.read_text(encoding="utf-8").splitlines())
        totals[category] += lines
        files.append({"path": path.relative_to(root).as_posix(), "category": category, "lines": lines})
print(json.dumps({"method": "nonblank noncomment physical .mbt lines; generated interfaces excluded", "totals": totals, "files": files}, indent=2))
