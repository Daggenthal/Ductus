#!/usr/bin/env python3
"""Build Ductus's Study grammar sets: the HSK grammar points (revised HSK 3.0
syllabus, 2025), each with real example sentences and their English translations.

Sources:
- Grammar points: the official HSK syllabus (CLEC, 2025), as text from
  https://github.com/krmanik/HSK-3.0 ("New HSK (2025)/HSK Grammar"), CC BY-SA 4.0.
- Example sentences: Tatoeba (https://tatoeba.org), CC BY 2.0 FR: Mandarin
  sentences, their English translations (cmn-eng links) and both authors.
  Download cmn_sentences_detailed.tsv, cmn-eng_links.tsv and
  eng_sentences_detailed.tsv (per-language exports) into one folder.
- English names of the points: scripts/grammar_labels.json; search patterns for points
  that describe a structure (HSK 1 and 2): scripts/grammar_patterns.json. Both written for Ductus.

A point's items ("会、能", "……在/正在+动词……+呢") become search patterns.
Sentences are kept when every word is in the HSK lists up to the point's
level (one level above if that gives too few). Points that describe a sentence
type ("动词谓语句") cannot be searched for; they are listed without examples.

Output: DuctusEngine/Sources/DuctusEngine/Resources/study-grammar-hsk<N>.tsv
    @ <tab> section <tab> title <tab> items <tab> English title
    typed <tab> characters (chunks joined by |) <tab> pinyin with tones (|) <tab> English <tab> cmn id <tab> eng id
and study-grammar-credits.tsv with each sentence's authors.

Usage (with the build tools from build_cjk_corpus.py installed):
    python3 scripts/build_grammar.py --grammar /path/to/grammar/txt --tatoeba /path/to/tatoeba
"""

import argparse
import collections
import json
import pathlib
import random
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import build_cjk_corpus as cjk  # noqa: E402
from blocklist import Blocklist  # noqa: E402

RESOURCES = cjk.RESOURCES
LEVELS = ["1", "2", "3", "4", "5", "6", "7-9"]
PER_ITEM = int(__import__('os').environ.get('GRAMMAR_PER_ITEM', 4))
PER_POINT = int(__import__('os').environ.get('GRAMMAR_PER_POINT', 8))
# Words for grammar categories: an item made of these describes a structure, not words to find.
TERMS = re.compile(r"(动词|名词|代词|数词|量词|形容词|副词|宾语|主语|谓语|补语|定语|状语|短语|句|表示|词语|结构|用法|数量|处所|"
                   r"时间|方式|程度|结果|趋向|可能|情态|动作|对象|原因|目的|条件|假设|转折|让步|选择|递进|并列|承接)")
PUNCT = "，。？！、：；“”‘’（）《》…—,.?!"


def parse(path):
    """Points from one level's text: (section, title, items) for each "- ..." line."""
    points = []
    headings = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        match = re.match(r"^(\d+(?:\.\d+)*)\.?\s*(.*)$", stripped)
        if match and not stripped.startswith("-"):
            number, title = match.groups()
            headings[number.count(".")] = (number, title.strip())
            for deeper in [k for k in headings if k > number.count(".")]:
                del headings[deeper]
            continue
        if stripped.startswith("-"):
            items = stripped[1:].strip()
            if not items or not headings:
                continue
            number, title = headings[max(headings)]
            if not title:  # "6.1" has no title of its own
                title = headings.get(max(headings) - 1, ("", ""))[1]
            top = headings.get(0, ("", ""))[1]
            points.append((number, top, title, items))
    return points


def patterns(items):
    """Search patterns for a point's items, or [] if it describes a structure."""
    text = re.sub(r"^（\d+）", "", items).strip()
    if "：" in text:
        label, rest = text.split("：", 1)
        text = rest if "、" in rest or len(rest) <= 6 else text
    found = []
    for item in re.split(r"[、，,]", text):
        item = item.strip().strip("“”")
        item = re.sub(r"(?<=[一-鿿])\d+", "", item)  # 都1 -> 都
        if not item:
            continue
        # Drop grammar terms joined with +: "在/正在+动词" -> "在/正在".
        parts = [p for p in item.split("+") if p and not TERMS.search(p)]
        if not parts or (TERMS.search(item) and not re.search(r"[“…/（]", item) and len(parts) < 1):
            continue
        item = "".join(parts)
        if TERMS.search(item) or re.search(r"[A-Za-z]", item):
            continue
        if "—" in item:  # morphemes: 小— (prefix), —们 (suffix)
            core = item.replace("—", "")
            found.append(("prefix" if item.endswith("—") else "suffix", core))
            continue
        segments = [s for s in re.split(r"……|…", item) if s.strip()]
        regex = ".*?".join("(?:" + "|".join(alternative(alt) for alt in seg.split("/")) + ")" for seg in segments)
        if not regex or not re.search(r"[一-鿿]", regex):
            continue
        if len(segments) == 1 and "/" not in item and "（" not in item:
            found.append(("word", segments[0]))
        else:
            found.append(("regex", regex))
    return found


def alternative(text):
    """One alternative of a pattern as a regex; （一） marks an optional part."""
    pieces = re.split(r"（([^（）]*)）", text)
    out = ""
    for i, piece in enumerate(pieces):
        piece = piece.replace("（", "").replace("）", "")
        out += f"(?:{re.escape(piece)})?" if i % 2 else re.escape(piece)
    return out


def matches(kind, value, words, text):
    if kind == "word":
        return value in words
    if kind == "prefix":
        return any(w.startswith(value) and len(w) > len(value) for w in words)
    if kind == "suffix":
        return any(w.endswith(value) and len(w) > len(value) for w in words)
    return re.search(value, text) is not None


def hsk_words(level_index):
    words = set()
    for n in range(1, level_index + 2):
        path = RESOURCES / f"study-hsk{n}.tsv"
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.startswith("#"):
                words.add(line.split("\t")[0])
    return words


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--grammar", type=pathlib.Path, required=True, help="folder with HSK 1.txt ... HSK 7-9.txt")
    parser.add_argument("--tatoeba", type=pathlib.Path, required=True)
    args = parser.parse_args()
    from pypinyin import Style, lazy_pinyin

    labels_path = pathlib.Path(__file__).resolve().parent / "grammar_labels.json"
    labels = json.loads(labels_path.read_text(encoding="utf-8")) if labels_path.exists() else {}
    # Hand-written search patterns for points that describe a structure (HSK 1 and 2).
    overrides = json.loads((labels_path.parent / "grammar_patterns.json").read_text(encoding="utf-8"))
    # Levels with hand-checked examples; other levels ship without examples
    # (set GRAMMAR_SEARCH=1 to list search results for reviewing).
    reviewed = json.loads((labels_path.parent / "grammar_reviewed.json").read_text(encoding="utf-8"))
    reviewed.pop("_about", None)
    reviewed.pop("_rejected", None)  # reasons for turned-down sentences, for reviewers
    search_unreviewed = __import__("os").environ.get("GRAMMAR_SEARCH") == "1"

    # English translations (first one per Chinese sentence) and their authors.
    links = collections.defaultdict(list)
    for line in (args.tatoeba / "cmn-eng_links.tsv").read_text(encoding="utf-8").splitlines():
        a, b = line.split("\t")[:2]
        links[a].append(b)
    wanted = {b for bs in links.values() for b in bs}
    english = {}
    with (args.tatoeba / "eng_sentences_detailed.tsv").open(encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 4 and parts[0] in wanted and parts[3] not in ("\\N", ""):
                english[parts[0]] = (parts[2], parts[3])

    rows = list(cjk.read_tatoeba(args.tatoeba / "cmn_sentences_detailed.tsv"))
    authors = {sid: author for sid, _, author in rows}
    _, _, sentences = cjk.build_chinese(rows, random.Random(42))
    blocklist = Blocklist("chinese", args.tatoeba)
    pool = []
    for sid, author, typed, native in sentences:
        chunks = native.split("|")
        eng = next((english[e] for e in links.get(sid, []) if e in english), None)
        if not eng or blocklist.blocks_text(native, chunks=chunks):
            continue
        words = [c.strip(PUNCT) for c in chunks]
        pool.append(dict(id=sid, author=author, typed=typed, chunks=chunks, words=words,
                         text="".join(chunks), english=eng[0], eng_id=next(e for e in links[sid] if e in english),
                         eng_author=eng[1]))
    print(f"{len(pool)} Chinese sentences with an English translation", file=sys.stderr)

    # Pinyin with tones per word: the HSK readings (CC-CEDICT, with neutral tones
    # like péng you and shéi) where the word is in the lists, else pypinyin.
    readings = {}
    for n in range(7, 0, -1):
        for line in (RESOURCES / f"study-hsk{n}.tsv").read_text(encoding="utf-8").splitlines():
            if not line.startswith("#"):
                parts = line.split("\t")
                readings[parts[0]] = parts[1].lower()

    def tone_pinyin(word, previous=""):
        if word == "只" and previous and previous[-1] in "这那哪每几一两三四五六七八九十":
            return "zhī"  # the measure word (这只狗), not zhǐ "only"
        if word in readings:
            text = readings[word]
        else:
            # Dictionary tones, as in the HSK lists: 一 is yī and 不 is bù, without tone changes.
            syllables = lazy_pinyin(word, style=Style.TONE)
            text = " ".join("yī" if c == "一" else "bù" if c == "不" else y for c, y in zip(word, syllables))
        # Erhua joins its syllable: 这儿 is zhèr, not zhè ér or zhè r.
        return re.sub(r" (?:ér|r)\b", "r", text) if "儿" in word else text

    def plain(tones):
        """Typed form of tone pinyin: no marks, v for ü, no spaces ("zhèr" -> "zher")."""
        import unicodedata
        text = re.sub("[ǖǘǚǜü]", "v", tones.lower())
        return "".join(c for c in unicodedata.normalize("NFD", text) if c.isascii() and c.isalpha())

    rng = random.Random(7)
    credits = {}
    for index, level in enumerate(LEVELS):
        source = args.grammar / f"hsk{level}.txt"
        points = parse(source)
        vocab = [hsk_words(index), hsk_words(min(index + 1, len(LEVELS) - 1))]
        out = [f"# HSK {level} grammar points (revised HSK 3.0 syllabus, 2025; list from krmanik/HSK-3.0, CC BY-SA 4.0). "
               "Example sentences: Tatoeba, CC BY 2.0 FR (authors in study-grammar-credits.tsv)."]
        with_examples = 0
        for number, top, title, items in points:
            english_title = labels.get(f"{title}|{items}") or labels.get(title, "")
            out.append("\t".join(["@", number, title, items, english_title]))
            chosen = []
            if level in reviewed:
                # Only examples checked by hand; a point without any gets none.
                by_id = {p["id"]: p for p in pool}
                chosen = [by_id[i] for i in reviewed[level].get(f"{number}|{items}", []) if i in by_id]
            pats = [] if level in reviewed or not search_unreviewed else (
                [tuple(p) for p in overrides.get(f"{level}|{number}|{items}", [])] or patterns(items))
            for words_allowed in vocab:
                if chosen or not pats:
                    break
                fits = [s for s in pool if all(w in words_allowed or not w for w in s["words"])]
                for kind, value in pats:
                    hits = [s for s in fits if matches(kind, value, s["words"], s["text"]) and s not in chosen]
                    hits.sort(key=lambda s: len(s["typed"]))
                    chosen += rng.sample(hits[:40], min(PER_ITEM, len(hits[:40])))
            chosen = chosen[:PER_POINT]
            if chosen:
                with_examples += 1
            for s in chosen:
                words = [c.strip(PUNCT) for c in s["chunks"]]
                tone_chunks = [tone_pinyin(w, words[i - 1] if i else "") for i, w in enumerate(words)]
                tones = "|".join(tone_chunks)
                # Typed form from the same readings, keeping each chunk's punctuation keys.
                typed = " ".join(plain(t) + re.sub(r"[a-z]", "", piece)
                                 for t, piece in zip(tone_chunks, s["typed"].split(" ")))
                out.append("\t".join([typed, "|".join(s["chunks"]), tones, s["english"], s["id"], s["eng_id"]]))
                credits[s["id"]] = s["author"]
                credits[s["eng_id"]] = s["eng_author"]
        (RESOURCES / f"study-grammar-hsk{level.split('-')[0]}.tsv").write_text("\n".join(out) + "\n", encoding="utf-8")
        print(f"HSK {level}: {len(points)} points, {with_examples} with example sentences", file=sys.stderr)
    with (RESOURCES / "study-grammar-credits.tsv").open("w", encoding="utf-8") as f:
        f.write("# Example sentences and translations from Tatoeba (https://tatoeba.org), CC BY 2.0 FR.\n")
        f.write("# tatoeba_sentence_id\tauthor\n")
        for sid, author in sorted(credits.items(), key=lambda x: int(x[0])):
            f.write(f"{sid}\t{author}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
