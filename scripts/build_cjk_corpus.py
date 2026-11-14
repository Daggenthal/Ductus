#!/usr/bin/env python3
"""Build Ductus's Japanese and Chinese word lists and sentences from Tatoeba.

You type the romanized form, the way you would into a macOS input method:
Japanese as kana-faithful romaji ("toukyou", "watashiha"), Chinese as toneless
pinyin with v for ü ("zhongwen", "lv"). The Japanese or Chinese text is shown
alongside.

Source: Tatoeba sentences (https://tatoeba.org), CC BY 2.0 FR. Download the
per-language "detailed" exports (they include each sentence's author):
    https://downloads.tatoeba.org/exports/per_language/jpn/jpn_sentences_detailed.tsv.bz2
    https://downloads.tatoeba.org/exports/per_language/cmn/cmn_sentences_detailed.tsv.bz2
and unpack them into one folder.

Build-time tools (not shipped with Ductus):
    fugashi (MIT) with unidic-lite (MIT wrapper, UniDic BSD): Japanese words and readings
    jieba (MIT): Chinese word splitting
    pypinyin (MIT): Chinese readings
    opencc-python-reimplemented (Apache 2.0): Traditional to Simplified Chinese

Usage:
    pip install fugashi unidic-lite jieba pypinyin opencc-python-reimplemented
    python3 scripts/build_cjk_corpus.py --tatoeba <folder> [--languages japanese,chinese]

Outputs, in DuctusEngine/Sources/DuctusEngine/Resources/:
    <language>-words.tsv      typed<TAB>count<TAB>native
    <language>-sentences.txt  typed<TAB>native chunks joined by "|"
    <language>-credits.tsv    Tatoeba sentence ID<TAB>author, for every shipped sentence
"""

import argparse
import collections
import pathlib
import random
import re
import sys

RESOURCES = pathlib.Path("DuctusEngine/Sources/DuctusEngine/Resources")
MAX_WORDS = 10_000
MIN_COUNT = 2
MAX_TYPED_LENGTH = 14
MAX_SENTENCES = 4000
SENTENCE_TYPED_LENGTH = (20, 120)

# Full-width punctuation to what you type for it in an input method.
PUNCTUATION = {"。": ".", "、": ",", "，": ",", "？": "?", "！": "!", "：": ":", "；": ";", "．": "."}

# ---------------------------------------------------------------- Japanese

KANA = {
    "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
    "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
    "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
    "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
    "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
    "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
    "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
    "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
    "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
    "ワ": "wa", "ヰ": "wi", "ヱ": "we", "ヲ": "wo",
    "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
    "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
    "ダ": "da", "ヂ": "di", "ヅ": "du", "デ": "de", "ド": "do",
    "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
    "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",
    "ヴ": "vu",
    "ァ": "xa", "ィ": "xi", "ゥ": "xu", "ェ": "xe", "ォ": "xo",
    "ャ": "xya", "ュ": "xyu", "ョ": "xyo", "ヮ": "xwa", "ヵ": "xka", "ヶ": "xke",
    "ー": "-",
}
# Two-kana sounds, as typed in an input method.
KANA_PAIRS = {
    "キャ": "kya", "キュ": "kyu", "キョ": "kyo", "ギャ": "gya", "ギュ": "gyu", "ギョ": "gyo",
    "シャ": "sha", "シュ": "shu", "ショ": "sho", "シェ": "she",
    "ジャ": "ja", "ジュ": "ju", "ジョ": "jo", "ジェ": "je",
    "チャ": "cha", "チュ": "chu", "チョ": "cho", "チェ": "che",
    "ニャ": "nya", "ニュ": "nyu", "ニョ": "nyo", "ヒャ": "hya", "ヒュ": "hyu", "ヒョ": "hyo",
    "ビャ": "bya", "ビュ": "byu", "ビョ": "byo", "ピャ": "pya", "ピュ": "pyu", "ピョ": "pyo",
    "ミャ": "mya", "ミュ": "myu", "ミョ": "myo", "リャ": "rya", "リュ": "ryu", "リョ": "ryo",
    "ヂャ": "dya", "ヂュ": "dyu", "ヂョ": "dyo",
    "ティ": "thi", "ディ": "dhi", "デュ": "dhu", "トゥ": "twu", "ドゥ": "dwu",
    "ファ": "fa", "フィ": "fi", "フェ": "fe", "フォ": "fo", "フュ": "fyu",
    "ウィ": "wi", "ウェ": "we", "ウォ": "who", "イェ": "ye",
    "ヴァ": "va", "ヴィ": "vi", "ヴェ": "ve", "ヴォ": "vo",
    "ツァ": "tsa", "ツィ": "tsi", "ツェ": "tse", "ツォ": "tso", "クァ": "kwa", "グァ": "gwa",
}
JAPANESE_TEXT = re.compile(r"^[ぁ-ゖァ-ヺー一-鿿々。、？！]+$")
# UniDic gives the formal reading for some everyday words.
READING_OVERRIDES = {"私": "ワタシ", "私達": "ワタシタチ", "私たち": "ワタシタチ"}
# Conjugation forms kept in the word list: uninflected, dictionary and attributive forms.
WORD_FORMS = {"*", "終止形-一般", "連体形-一般", None}
CONTENT_POS = {"名詞", "代名詞", "動詞", "形容詞", "形状詞", "副詞", "連体詞", "接続詞", "感動詞", "接頭辞"}


def to_romaji(katakana: str) -> str | None:
    """Kana-faithful romaji for a katakana reading, or None if it has anything else."""
    out = []
    i = 0
    while i < len(katakana):
        pair = katakana[i:i + 2]
        if pair in KANA_PAIRS:
            out.append(KANA_PAIRS[pair])
            i += 2
            continue
        ch = katakana[i]
        if ch == "ッ":
            out.append("ッ")  # resolved below, once the next sound is known
        elif ch == "ン":
            out.append("ン")
        elif ch in KANA:
            out.append(KANA[ch])
        else:
            return None
        i += 1
    # ッ doubles the next consonant ("kitte"), ン is "nn" before a vowel, y or n.
    result = []
    for index, piece in enumerate(out):
        following = out[index + 1] if index + 1 < len(out) else ""
        if piece == "ッ":
            result.append(following[0] if following and following[0] not in "aiueon-ッン" else "xtsu")
        elif piece == "ン":
            result.append("nn" if following and following[0] in "aiueoyn" else "n")
        else:
            result.append(piece)
    return "".join(result)


def build_japanese(rows, rng):
    import fugashi
    tagger = fugashi.Tagger()
    counts = collections.Counter()
    natives = collections.defaultdict(collections.Counter)
    sentences = []

    for sentence_id, text, author in rows:
        text = text.strip()
        tokens = list(tagger(text))
        ok_sentence = bool(JAPANESE_TEXT.match(text))
        chunks = []  # [katakana reading, native, punctuation typed after it]
        previous_pos = None
        for token in tokens:
            surface = token.surface
            feature = token.feature
            pos1, pos2 = feature.pos1, feature.pos2
            if surface in PUNCTUATION:
                if chunks:
                    chunks[-1][2] += PUNCTUATION[surface]
                    chunks[-1][1] += surface
                else:
                    ok_sentence = False
                previous_pos = pos1
                continue
            reading = READING_OVERRIDES.get(surface) or (feature.kana if feature.kana and feature.kana != "*" else None)
            romaji = to_romaji(reading) if reading else None
            if romaji is None:
                ok_sentence = False
                previous_pos = pos1
                continue
            # Word list: dictionary words, no names, no symbols or numbers.
            # Fragments ending in ッ ("悲しかっ") are not words on their own.
            # Inflecting words only in dictionary form ("押す", not the stem "押さ").
            if pos1 not in {"補助記号", "記号", "空白"} and pos2 != "固有名詞" and pos2 != "数詞" \
                    and feature.cForm in WORD_FORMS and "-" not in romaji and not reading.endswith("ッ") and len(romaji) <= MAX_TYPED_LENGTH:
                counts[romaji] += 1
                natives[romaji][surface] += 1
            # Typing chunks: a word plus its particles and endings.
            starts = pos1 in CONTENT_POS and pos2 != "非自立可能" and previous_pos != "接頭辞"
            if starts or not chunks or chunks[-1][2]:
                chunks.append([reading, surface, ""])
            else:
                chunks[-1][0] += reading
                chunks[-1][1] += surface
            previous_pos = pos1

        if ok_sentence and author and chunks:
            # Each chunk is romanized as a whole, so ッ and ン see the next sound.
            typed = " ".join(to_romaji(c[0]) + c[2] for c in chunks)
            if SENTENCE_TYPED_LENGTH[0] <= len(typed) <= SENTENCE_TYPED_LENGTH[1] and typed[-1] in ".?!":
                sentences.append((sentence_id, author, typed, "|".join(c[1] for c in chunks)))
    return counts, natives, sentences


# ---------------------------------------------------------------- Chinese

HAN = re.compile(r"^[一-鿿]+$")
CHINESE_TEXT = re.compile(r"^[一-鿿。，、？！：；]+$")
# jieba part-of-speech flags for names: people, places, organizations, other proper nouns.
NAME_FLAGS = {"nr", "nrfg", "nrt", "ns", "nt", "nz"}


def build_chinese(rows, rng):
    import jieba
    import jieba.posseg
    import opencc
    from pypinyin import Style, lazy_pinyin
    jieba.setLogLevel(60)
    to_simplified = opencc.OpenCC("t2s")
    counts = collections.Counter()
    natives = collections.defaultdict(collections.Counter)
    sentences = []

    for sentence_id, text, author in rows:
        text = to_simplified.convert(text.strip())
        ok_sentence = bool(CHINESE_TEXT.match(text))
        chunks = []
        for pair in jieba.posseg.cut(text):
            word, flag = pair.word, pair.flag
            if word in PUNCTUATION:
                if chunks:
                    chunks[-1][0] += PUNCTUATION[word]
                    chunks[-1][1] += word
                else:
                    ok_sentence = False
                continue
            if not HAN.match(word):
                ok_sentence = False
                continue
            # Toneless pinyin, ü as v ("lv"), syllables joined like in an input method.
            pinyin = "".join(lazy_pinyin(word, style=Style.NORMAL))
            if not pinyin.isascii() or not pinyin.isalpha():
                ok_sentence = False
                continue
            if flag not in NAME_FLAGS and len(pinyin) <= MAX_TYPED_LENGTH:
                counts[pinyin] += 1
                natives[pinyin][word] += 1
            chunks.append([pinyin, word])

        if ok_sentence and author and chunks:
            typed = " ".join(c[0] for c in chunks)
            if SENTENCE_TYPED_LENGTH[0] <= len(typed) <= SENTENCE_TYPED_LENGTH[1] and typed[-1] in ".?!":
                sentences.append((sentence_id, author, typed, "|".join(c[1] for c in chunks)))
    return counts, natives, sentences


# ---------------------------------------------------------------- Output

SOURCES = {"japanese": ("jpn", build_japanese), "chinese": ("cmn", build_chinese)}


def read_tatoeba(path: pathlib.Path):
    """(id, text, author) rows. Sentences with no owner have author None."""
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        author = parts[3] if parts[3] not in ("\\N", "") else None
        yield parts[0], parts[2], author


def build(language: str, tatoeba: pathlib.Path) -> None:
    code, builder = SOURCES[language]
    rng = random.Random(42)
    rows = list(read_tatoeba(tatoeba / f"{code}_sentences_detailed.tsv"))
    counts, natives, sentences = builder(rows, rng)

    kept = [(typed, n) for typed, n in counts.items() if n >= MIN_COUNT and typed.isalpha()]
    kept.sort(key=lambda item: (-item[1], item[0]))
    kept = kept[:MAX_WORDS]
    with (RESOURCES / f"{language}-words.tsv").open("w", encoding="utf-8") as f:
        for typed, n in kept:
            native = natives[typed].most_common(1)[0][0]
            f.write(f"{typed}\t{n}\t{native}\n")
    print(f"{language}: {len(kept)} words from {len(rows)} sentences", file=sys.stderr)

    unique = list({s[2]: s for s in sentences}.values())  # one per typed text
    unique.sort(key=lambda s: int(s[0]))
    sample = rng.sample(unique, min(MAX_SENTENCES, len(unique)))
    sample.sort(key=lambda s: int(s[0]))
    with (RESOURCES / f"{language}-sentences.txt").open("w", encoding="utf-8") as f:
        for _, _, typed, native in sample:
            f.write(f"{typed}\t{native}\n")
    with (RESOURCES / f"{language}-credits.tsv").open("w", encoding="utf-8") as f:
        f.write("# Sentences from Tatoeba (https://tatoeba.org), CC BY 2.0 FR.\n")
        f.write("# Romanized and split into chunks for typing" + (", converted to Simplified Chinese" if language == "chinese" else "") + ".\n")
        f.write("# tatoeba_sentence_id\tauthor\n")
        for sentence_id, author, _, _ in sample:
            f.write(f"{sentence_id}\t{author}\n")
    print(f"{language}: {len(sample)} of {len(unique)} sentences", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tatoeba", required=True, type=pathlib.Path, help="folder with the unpacked exports")
    parser.add_argument("--languages", default="japanese,chinese")
    args = parser.parse_args()
    for language in args.languages.split(","):
        if language not in SOURCES:
            print(f"unknown language {language}", file=sys.stderr)
            return 1
        build(language, args.tatoeba)
    return 0


if __name__ == "__main__":
    sys.exit(main())
