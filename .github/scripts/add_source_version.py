#!/usr/bin/env python3
"""Add a release to the top of source.json (AltStore source).

Usage: add_source_version.py <tag> <ipa path> <release notes>
Run from the repository root.
"""

import json
import os
import re
import sys
import urllib.parse
from datetime import datetime

tag, ipa_path, notes = sys.argv[1:4]
match = re.fullmatch(r"v?(\d+\.\d+\.\d+)\+(\d+)", tag)
if not match:
    sys.exit(f"Tag {tag} is not like v1.2.3+45")
version, build = match.groups()

with open("ios/Runner.xcodeproj/project.pbxproj") as f:
    min_os = re.search(r"IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);", f.read()).group(1)

with open("source.json") as f:
    source = json.load(f)

app = source["apps"][0]
app["versions"] = [v for v in app["versions"] if v.get("buildVersion") != build]
app["versions"].insert(
    0,
    {
        "downloadURL": "https://github.com/NekoSurf/NekoSurf/releases/download/"
        f"{urllib.parse.quote(tag)}/{os.path.basename(ipa_path)}",
        "size": os.path.getsize(ipa_path),
        "version": version,
        "buildVersion": build,
        "date": datetime.now().astimezone().isoformat(timespec="seconds"),
        "localizedDescription": notes,
        "minOSVersion": min_os,
    },
)

with open("source.json", "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
    f.write("\n")
