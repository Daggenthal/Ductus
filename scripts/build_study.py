#!/usr/bin/env python3
"""Build Ductus's Study word sets: HSK 1 to 7-9 (revised HSK 3.0 syllabus, 2025).

Source: complete-hsk-vocabulary by Yanis Zafirópulos (MIT),
https://github.com/drkameleon/complete-hsk-vocabulary. Download complete.json
from it. Its English meanings come from CC-CEDICT (https://cc-cedict.org,
CC BY-SA 4.0), so the meanings in the output stay under CC BY-SA 4.0.

Output, one file per level (DuctusEngine/Sources/DuctusEngine/Resources/study-hsk<N>.tsv):
    characters <tab> pinyin <tab> typed <tab> meaning
most common first. `typed` is what you type: toneless pinyin with v for ü ("nihao").

Usage:
    python3 scripts/build_study.py --source /path/to/complete.json
"""

import argparse
import json
import pathlib
import re
import sys
import unicodedata

RESOURCES = pathlib.Path(__file__).resolve().parent.parent / "DuctusEngine/Sources/DuctusEngine/Resources"
LEVELS = {"1": "newest-1", "2": "newest-2", "3": "newest-3", "4": "newest-4", "5": "newest-5", "6": "newest-6",
          "7": "newest-7"}
# CC-CEDICT entries that are not the everyday sense of a word.
JUNK = re.compile(r"^(surname |old variant|variant of|used in |\(archaic\)|\(onom|see |also written|abbr\. for|"
                  r"erhua variant|\(old\)|\(dialect\)|\(literary\)|Japanese variant|\(Tw\)|\(Cantonese\))", re.I)
# Words where the rule above picks a rarer reading; checked by hand.
READINGS = {"吗": "ma", "喝": "hē", "雨": "yǔ"}
MAX_MEANINGS = 3


def score(form):
    good = [m for m in form["meanings"] if not JUNK.match(m)]
    value = len(good) * 2 - (len(form["meanings"]) - len(good)) * 3
    if form["transcriptions"]["pinyin"][:1].isupper():
        value -= 20  # names
    return value


def pick(word):
    if word["simplified"] in READINGS:
        wanted = READINGS[word["simplified"]]
        for form in word["forms"]:
            if form["transcriptions"]["pinyin"] == wanted:
                return form
    return max(word["forms"], key=score)


def typed(numeric, pinyin):
    """'ni3 hao3' -> 'nihao', 'lü4' -> 'lv'. A few entries have tone marks instead of
    numbers ('diàndòngchē'), so those are read from the pinyin without its marks."""
    key = re.sub(r"[\d\s]", "", numeric).replace("ü", "v").replace("u:", "v").lower()
    if key.isascii():
        return key
    plain = re.sub("[ǖǘǚǜü]", "v", pinyin.lower())
    plain = unicodedata.normalize("NFD", plain)
    return "".join(c for c in plain if c.isascii() and c.isalpha())


def meaning(form):
    meanings = [m for m in form["meanings"] if not JUNK.match(m)] or form["meanings"]
    return "; ".join(meanings[:MAX_MEANINGS]).replace("\t", " ")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=pathlib.Path, required=True, help="complete.json")
    args = parser.parse_args()
    words = json.loads(args.source.read_text(encoding="utf-8"))
    for level, tag in LEVELS.items():
        chosen = sorted((w for w in words if tag in w["level"]), key=lambda w: w["frequency"])
        rows = []
        for word in chosen:
            form = pick(word)
            key = typed(form["transcriptions"]["numeric"], form["transcriptions"]["pinyin"])
            if not key.isalpha() or not key.isascii():
                print(f"hsk{level}: skipped {word['simplified']} ({key})", file=sys.stderr)
                continue
            rows.append(f"{word['simplified']}\t{re.sub(r'\d', '', form['transcriptions']['pinyin'])}\t{key}\t{meaning(form)}")
        path = RESOURCES / f"study-hsk{level}.tsv"
        header = ("# HSK " + ("7-9" if level == "7" else level) + " (revised HSK 3.0 syllabus, 2025). Word list: "
                  "complete-hsk-vocabulary (MIT). Meanings: CC-CEDICT, CC BY-SA 4.0.\n")
        path.write_text(header + "\n".join(rows) + "\n", encoding="utf-8")
        print(f"hsk{level}: {len(rows)} words", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
