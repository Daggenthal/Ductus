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
    typed <tab> characters (chunks joined by |) <tab> pinyin with tones (|) <tab> English <tab> cmn id <tab> eng id <tab> highlights
(the point line ends with the words to highlight; highlights are character ranges "start-end;...")
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


GRAMMAR_WORDS = re.compile(r"(动词|名词|代词|数词|量词|形容词|副词|宾语|主语|谓语|补语|定语|状语|短语|句|表示|词语|结构|用法|"
                           r"数量|处所|所处|时间|地点|方式|动作者|对象|原因|状态|持续|专用|借用|用动态助词|序数|概数|连接|选择|问)")


def markers(items):
    """The words of a point to highlight in its examples: 会、能 -> 会, 能;
    "（4）A比B+动词+得+形容词" -> 比, 得; 用“还是”连接的选择问句 -> 还是."""
    quoted = re.findall(r"“([^”]+)”", items)
    if quoted:
        return [re.sub(r"\d", "", q) for q in quoted]
    text = re.sub(r"（\d+）|\d+|\(.*?\)|（.*?）", "", items)
    if "：" in text:
        text = text.split("：", 1)[1]
    found = []
    for part in re.split(r"[、，,+/…—\s]+|……", text):
        part = part.strip("“”（）()")
        if part and re.fullmatch(r"[\u4e00-\u9fff]{1,3}", part) and not GRAMMAR_WORDS.search(part):
            found.append(part)
    return found


def mark_ranges(text, words):
    """Character ranges of the marker words in a sentence, as "start-end;start-end"."""
    spans = []
    for word in sorted(set(words), key=len, reverse=True):
        for m in re.finditer(re.escape(word), text):
            if not any(a < m.end() and m.start() < b for a, b in spans):
                spans.append((m.start(), m.end()))
    return ";".join(f"{a}-{b}" for a, b in sorted(spans))


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
    translations = reviewed.pop("_translations", {})
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
    # Word breaks set by hand where the word splitter gets a sentence wrong.
    chunk_fixes = json.loads((pathlib.Path(__file__).resolve().parent / "grammar_reviewed.json").read_text(encoding="utf-8")).get("_chunks", {})
    authors = {sid: author for sid, _, author in rows}
    _, _, sentences = cjk.build_chinese(rows, random.Random(42))
    blocklist = Blocklist("chinese", args.tatoeba)
    pool = []
    for sid, author, typed, native in sentences:
        chunks = native.split("|")
        if sid in chunk_fixes:
            chunks = chunk_fixes[sid].split("|")
            typed = " ".join(cjk.PUNCTUATION.get(c[-1], "") for c in chunks)
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

    PRONOUNS = "我你他她它谁们"
    NUMBERS = "一二两三四五六七八九十几每某各这那哪"

    def char_reading(char, guess, before, after, in_word, sentence="", first_in_chunk=True, chunk_text=""):
        before, after = before or "\0", after or "\0"  # "" is "in" every string
        """One character's reading from its neighbors, for characters with several
        readings that pypinyin often gets wrong. `guess` is pypinyin's reading in
        the sentence's context; `before`/`after` are the neighboring characters."""
        if char == "一":
            return "yī"  # dictionary tone, as in the HSK lists
        if char == "不":
            return "bù"
        if char == "着":
            if before in "不得":
                return "zháo"  # 用不着, 睡不着, 犯得着
            if before in "睡找猜" and after == "了":
                return "zháo"  # 睡着了 "fell asleep"
            return guess if in_word else "zhe"
        if char == "得":
            # 也得去, 我得去, 现在得走: must (děi), before a verb and after a person, time or adverb.
            if before in "也就还总都我你他她们在天候" and after not in "到出了很\0" and not in_word:
                return "děi"
            return guess if in_word else "de"
        if char == "地" and not in_word:
            # The adverb particle (高兴地, 断然地, a split like 地笑) is de; 地上, 地球, 外地人 are dì.
            if chunk_text == "地" or (chunk_text.endswith("地") and len(chunk_text) >= 3) or (
                    chunk_text.startswith("地") and len(chunk_text) == 2 and after in "笑走说看跑吃做学写想哭叫喊点问"):
                return "de"
            return "dì"
        if char == "只":
            return "zhī" if before and before in NUMBERS + "像" else "zhǐ"
        if char == "长" and not in_word:
            return "zhǎng" if after in "大得高出成" or (before and before in "生成增队校家部班") else "cháng"
        if char == "倒" and not in_word:
            if before in "病摔跌滑打推放累晕":
                return "dǎo"  # 病倒了 "fell ill"
            return "dào" if after in "是也不挺很还还好像" else guess
        if char == "教" and not in_word:
            return "jiāo"
        if char == "为" and not in_word:
            return "wéi" if before in "成作称认改分以选之大较更极最" or after == "止" or ("选" in sentence and "为" in sentence) else "wèi"
        if char == "种" and not in_word:
            if before and before in NUMBERS:
                return "zhǒng"
            if (before and before in PRONOUNS) or after in "了的树花菜地过":
                return "zhòng"
        if char == "中" and not in_word:
            return "zhòng" if after in "了过奖" else "zhōng"
        if char == "重" and not in_word:
            return "chóng" if after in "新复" or before in "一两双多层" else "zhòng"
        if char == "和" and not in_word:
            return "hé"  # "and / with"; huó and huò only appear inside words
        if char == "还" and not in_word:
            return "huán" if after in "给书钱上清" else "hái"
        if char == "谁":
            return "shéi"  # as in the HSK lists
        if char == "了" and not in_word:
            return "liǎo" if before == "不" else "le"  # 做不了 "can't do"
        if char == "处" and not in_word:
            return "chǔ" if after in "理于在分境罚" else "chù"  # 处理 chǔ; 无处 / 此处 chù
        if char == "觉" and not in_word:
            return "jiào" if before in "好午睡个场" else "jué"  # 睡个觉, 睡午觉
        if char == "趟":
            return "tàng"
        if char == "吓" and after != "唬":
            return "xià"  # 吓得 xià de; hè only in 恐吓 (a dictionary word)
        if char == "转" and not in_word:
            return "zhuàn" if after == "圈" else "zhuǎn"
        return guess

    def sentence_tones(chunks, override=None):
        """Pinyin with tones for each chunk of a sentence: the HSK reading for words in
        the lists (CC-CEDICT, with neutral tones like péng you), else pypinyin read in
        the whole sentence's context, corrected by `char_reading`."""
        words = [c.strip(PUNCT) for c in chunks]
        text = "".join(words)
        han = [c for c in text if "\u4e00" <= c <= "\u9fff"]
        guesses = lazy_pinyin("".join(han), style=Style.TONE)
        guess_of = iter(guesses)
        out = []
        position = 0
        for index, word in enumerate(words):
            if override and index in override:
                out.append(override[index])
                position += len(word)
                for _ in word:
                    next(guess_of, None)
                continue
            # Verb + 着 is zhe (穿着 "wearing", not the noun chuānzhuó).
            verb_zhe = len(word) == 2 and word.endswith("着") and word not in ("睡着", "着急", "找着", "着火")
            if word == "得到" and index > 0 and len(words[index - 1]) == 1 and words[index - 1] in "做看听找买办说想见拿吃学":
                text_reading = "de dào"  # 做得到 "can do", not dé dào "obtain"
                for _ in word:
                    next(guess_of, None)
            elif word in readings and len(word) > 1 and not verb_zhe:
                text_reading = readings[word]
                for c in word:
                    if "\u4e00" <= c <= "\u9fff":
                        next(guess_of, None)
            else:
                syllables = []
                for i, char in enumerate(word):
                    if not ("\u4e00" <= char <= "\u9fff"):
                        continue
                    guess = next(guess_of, "")
                    before = text[position + i - 1] if position + i > 0 else ""
                    after = text[position + i + 1] if position + i + 1 < len(text) else ""
                    single = readings.get(char) if len(word) == 1 else None
                    if verb_zhe and char == "着":
                        syllables.append("zhe")
                    elif single and char not in "一不着得地只长倒教为种中重转还了和趟吓处觉谁":
                        syllables.append(single)
                    else:
                        syllables.append(char_reading(char, guess, before, after,
                                                      in_word=len(word) > 1 and word in readings, sentence=text,
                                                      first_in_chunk=i == 0, chunk_text=word))
                text_reading = " ".join(syllables)
            position += len(word)
            # Erhua joins its syllable: 这儿 is zhèr, not zhè ér.
            text_reading = text_reading.replace("u:", "ü")  # CC-CEDICT writes ü as u: (lu:è is lüè)
            # Erhua joins its syllable: 这儿 is zhèr, 看头儿 kàn tour.
            out.append(re.sub(r" (?:ér|er|r)\b", "r", text_reading) if "儿" in word else text_reading)
        return out

    def plain(tones):
        """Typed form of tone pinyin: no marks, v for ü, no spaces ("zhèr" -> "zher")."""
        import unicodedata
        text = re.sub("[ǖǘǚǜü]", "v", tones.lower())
        return "".join(c for c in unicodedata.normalize("NFD", text) if c.isascii() and c.isalpha())

    import jieba
    ai_count = [0]

    def ai_sentence(entry, allowed):
        """A sentence written by Claude where no human one fit: split into words like
        the Tatoeba ones, with words above the level reported for review."""
        ai_count[0] += 1
        chunks = []
        # "|" marks word breaks by hand where the word splitter gets them wrong.
        words_in = entry["ai"].split("|") if "|" in entry["ai"] else jieba.cut(entry["ai"])
        # A chunk never spans punctuation: "去，不" becomes "去，" and "不".
        words_in = [piece for w in words_in for piece in re.findall(r"[^，。？！、：；]+[，。？！、：；]*|[，。？！、：；]+", w)]
        for word in [w for part in words_in for w in ([part] if "|" in entry["ai"] else [part])]:
            if word in cjk.PUNCTUATION and chunks:
                chunks[-1] += word
            else:
                chunks.append(word)
        typed = " ".join(cjk.PUNCTUATION.get(c[-1], "") if c[-1] in cjk.PUNCTUATION else "" for c in chunks)
        above = [c.strip(PUNCT) for c in chunks if c.strip(PUNCT) not in allowed and not re.fullmatch(r"[一二两三四五六七八九十百千万零]+", c.strip(PUNCT))]
        if above:
            print(f"  AI sentence {entry['ai']}: words outside the level: {' '.join(above)}", file=sys.stderr)
        return dict(id=f"ai-{ai_count[0]}", typed=typed, chunks=chunks, english=entry["en"], eng_id="", eng_author="",
                    author="", text="".join(chunks), words=[c.strip(PUNCT) for c in chunks])

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
            point_markers = markers(items)
            out.append("\t".join(["@", number, title, items, english_title, "、".join(point_markers)]))
            chosen = []
            if level in reviewed:
                # Only examples checked by hand; a point without any gets none.
                by_id = {p["id"]: p for p in pool}
                for entry in reviewed[level].get(f"{number}|{items}", []):
                    if isinstance(entry, dict):
                        chosen.append(ai_sentence(entry, vocab[0]))
                    elif entry in by_id:
                        chosen.append(by_id[entry])
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
                tone_chunks = sentence_tones(s["chunks"])
                tones = "|".join(tone_chunks)
                # Typed form from the same readings, keeping each chunk's punctuation keys.
                typed = " ".join(plain(t) + re.sub(r"[a-z]", "", piece)
                                 for t, piece in zip(tone_chunks, s["typed"].split(" ")))
                english_text = s["english"]
                choice = translations.get("choose", {}).get(s["id"])
                if choice and choice in english:
                    english_text, s["eng_id"], s["eng_author"] = english[choice][0], choice, english[choice][1]
                english_text = translations.get("correct", {}).get(s["id"], english_text)
                marks = mark_ranges("".join(s["chunks"]), point_markers)
                out.append("\t".join([typed, "|".join(s["chunks"]), tones, english_text, s["id"], s["eng_id"], marks]))
                if not s["id"].startswith("ai-"):
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
