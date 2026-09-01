"""Builds Stackify.ps1 by combining the template + embedded app/tweak JSON.
Run this whenever config/apps.json or config/tweaks.json changes.
Not shipped to end users -- Stackify.ps1 is the single-file deliverable.
"""
import json
from pathlib import Path

HERE = Path(__file__).parent
apps = json.loads((HERE / "apps_clean.json").read_text(encoding="utf-8"))
tweaks = json.loads((HERE / "tweaks_clean.json").read_text(encoding="utf-8"))

apps_json = json.dumps(apps, separators=(",", ":"))
tweaks_json = json.dumps(tweaks, separators=(",", ":"))

# PowerShell here-strings can't contain a line that is exactly '@ at col 0
# followed by a quote sequence matching the terminator; our JSON is single-line
# so that's not a risk. Escape none needed for '@'...'@ single-quoted here-string
# since PowerShell does not interpolate inside it -- just must not contain the
# literal terminator sequence on its own line, which single-line JSON can't.

template = (HERE / "Stackify.template.ps1").read_text(encoding="utf-8")
out = template.replace("__APPS_JSON__", apps_json).replace("__TWEAKS_JSON__", tweaks_json)

out_path = HERE / "Stackify.ps1"
out_path.write_text(out, encoding="utf-8", newline="\n")
print(f"Wrote {out_path} ({len(out)} bytes)")
