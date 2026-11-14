#!/usr/bin/env python3
"""Fails if any interface text is missing a translation.

Asks Xcode for every localizable string in the app (xcodebuild
-exportLocalizations) and checks that each one is in Ductus/Localizable.xcstrings
with all languages. Run it after adding or changing UI text:

    python3 scripts/check_translations.py
"""

import glob
import json
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

LANGUAGES = ["en", "fr", "es", "de", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko"]
NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}

root = pathlib.Path(__file__).resolve().parent.parent
catalog = json.loads((root / "Ductus/Localizable.xcstrings").read_text())["strings"]

with tempfile.TemporaryDirectory() as out:
    subprocess.run(
        ["xcodebuild", "-exportLocalizations", "-project", str(root / "Ductus.xcodeproj"),
         "-localizationPath", out, "-exportLanguage", "fr"],
        check=True, capture_output=True,
    )
    xliff = glob.glob(f"{out}/**/*.xliff", recursive=True)[0]
    in_app = set()
    for file in ET.parse(xliff).getroot().findall("x:file", NS):
        if file.get("original", "").endswith(("Localizable.strings", "Localizable.xcstrings")):
            in_app |= {unit.get("id") for unit in file.findall(".//x:trans-unit", NS)}

problems = []
for key in sorted(in_app):
    have = set(catalog.get(key, {}).get("localizations", {}))
    if missing := [lang for lang in LANGUAGES if lang not in have]:
        problems.append(f"  {key!r}: missing {', '.join(missing)}")

if problems:
    print(f"{len(problems)} interface string(s) need translations in Ductus/Localizable.xcstrings:")
    print("\n".join(problems))
    sys.exit(1)
print(f"All {len(in_app)} interface strings are translated into {len(LANGUAGES)} languages.")
