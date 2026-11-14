#!/usr/bin/env python3
"""Fails if any interface text is missing a translation.

1. Asks Xcode for every localizable string in the app (xcodebuild
   -exportLocalizations) and checks that each one is in
   Ductus/Localizable.xcstrings with all languages.
2. Scans the code for English words chosen in code and shown as plain text
   (which Xcode cannot see as translatable).

Run it after adding or changing UI text:

    python3 scripts/check_translations.py
"""

import glob
import json
import re
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

LANGUAGES = ["en", "fr", "es", "de", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko", "ru", "uk", "ar", "tr", "pl", "cs", "hu", "el", "he", "fa", "hi"]
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

# Plain text that reaches the screen without going through the catalog: English
# words chosen in code (`? "Locked" : ...`, `?? "Start"`, `map { "next ..." }`).
# SwiftUI only translates text written directly inside Text("...") and similar,
# so these must use String(localized:, bundle: .ui) instead. Mark a line with
# `// not UI` if the text is never shown (an ID, a default value).
PLAIN = re.compile(r'(\? "|\?\? "|\{ "|^\s*: ")[A-Za-z][a-z]')
SKIP = ("String(localized", "Log.", "forKey", "SettingsKey", "systemImage", "rawValue", "identifier",
        "fileExtension", "withExtension", "forResource", "contentType", "Keys.", "UTType", "ofType",
        "environment[", "URL(string", "#Predicate", "// not UI")
plain = []
for path in sorted((root / "Ductus").rglob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        # An enum's raw value shown as a label (Text($0.rawValue)) is never translated either.
        shows_raw = re.search(r"Text\([^)]*\.rawValue\)", line)
        if (PLAIN.search(line) or shows_raw) and not any(skip in line for skip in SKIP):
            plain.append(f"  {path.relative_to(root)}:{number}: {line.strip()[:110]}")

problems = []
if plain:
    problems.append("Text shown without translation (use String(localized: ..., bundle: .ui)):")
    problems += plain
for key in sorted(in_app):
    have = set(catalog.get(key, {}).get("localizations", {}))
    if missing := [lang for lang in LANGUAGES if lang not in have]:
        problems.append(f"  {key!r}: missing {', '.join(missing)}")

if problems:
    print("Some interface text is not translated:")
    print("\n".join(problems))
    sys.exit(1)
print(f"All {len(in_app)} interface strings are translated into {len(LANGUAGES)} languages.")
