"""Swear words and slurs to keep out of Ductus's word lists and sentences.

Uses the "List of Dirty, Naughty, Obscene, and Otherwise Bad Words" (LDNOOBW,
https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words),
licensed CC BY 4.0. The lists are downloaded into the build cache when the
corpus is built; they are not shipped with the app.

Spaced languages match whole words (so "class" and "passage" stay). Japanese,
Chinese and Korean are checked word by word (the build splits their text into
words): a word is blocked if it is a listed term or starts with one (particles
attach at the end of a word). Single-character terms are ignored there:
characters like 性 or 奶 are in many everyday words (性格, 牛奶).
"""

import base64
import pathlib
import re
import time
import urllib.request

URL = "https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/{code}"
CODES = {
    "english": "en", "french": "fr", "spanish": "es", "german": "de", "italian": "it",
    "portuguese": "pt", "dutch": "nl", "japanese": "ja", "chinese": "zh", "korean": "ko",
    "arabic": "ar", "russian": "ru", "turkish": "tr", "polish": "pl", "czech": "cs", "hungarian": "hu",
    "persian": "fa", "hindi": "hi",
    # LDNOOBW has no Greek or Hebrew list: those use only the EXTRA words below.
    "greek": None, "hebrew": None,
    # LDNOOBW has no Ukrainian list; the Russian one covers most of the same words.
    "ukrainian": "ru",
}
UNSPACED = {"japanese", "chinese", "korean"}
# Words LDNOOBW lists that are ordinary in everyday use (and common in the
# books and sentences). Slurs, explicit words and direct insults stay blocked.
ALLOW = {
    "english": {"intercourse", "escort", "snatch", "suck", "fingering"},
    "french": {"folle", "jouir", "gerbe", "bourré"},
    "spanish": {"infierno", "maldito", "asesinato", "concha"},
    "german": {"nackt", "vögeln"},  # "Vögeln" in the list is the noun: birds
    "italian": {"regina", "battere", "cadavere", "pesce", "tirare", "porco", "montare", "pompa"},
    "portuguese": {"comer", "inferno", "burro", "pau", "gozar", "cerveja", "consolo", "saco", "amador", "aranha"},
    "dutch": {"beurt", "nicht", "pot", "paal", "hol", "pijpen", "gat", "naakt", "standje", "naaien", "palen",
              "poot", "zuigen", "muts", "bekken", "lummel", "wippen", "aftrekken", "rukken"},
    "chinese": {"比", "既", "行", "掉", "承认", "草", "奶", "积极", "业绩", "强健", "激情", "乳房", "月经"},
    "japanese": {"成功", "女の子", "嫌い", "支配", "いたずら", "いたずらっ子", "誘惑", "奴隷", "人種", "滑らか",
                 "ファックス", "校門", "写生", "噴出", "無声", "拷問", "なめる", "女装", "おしっこ"},
    "korean": {"망가졌다", "망가뜨렸다"},
    "polish": {"jajko", "jajka", "jajek", "dmuchać"},  # egg, to blow
    "czech": {"bordel", "žrát"},  # mess, to eat
    "hungarian": {"marha", "marhák", "marhákat", "marhát", "marhahús", "pele"},  # cattle, dormouse
    "persian": {"کس", "سوپر", "برهنه", "لخت", "تجاوز", "شهوت"},  # person, super, naked, violation, desire
    "hebrew": {"מזונות", "בזיון"},  # food, disgrace (not the words they contain)
}

# Additions to LDNOOBW for words it misses.
EXTRA = {
    # Base64 so the words do not show up when reading the repo. Kana folding
    # covers the katakana spellings too.
    # LDNOOBW's Hindi list is in Latin letters (Hinglish), so Devanagari needs its own.
    "hindi": {base64.b64decode(w).decode() for w in ("4KSa4KWC4KSk4KS/4KSv4KS+", "4KSa4KWB4KSk4KS/4KSv4KS+", "4KSt4KWL4KS44KSh4KS84KWA", "4KSt4KWL4KS44KSh4KS84KWA4KSV4KWH", "4KSu4KS+4KSm4KSw4KSa4KWL4KSm", "4KSs4KS54KSo4KSa4KWL4KSm", "4KSt4KWH4KSo4KSa4KWL4KSm", "4KSw4KSC4KSh4KWA", "4KSw4KSj4KWN4KSh4KWA", "4KS54KSw4KS+4KSu4KWA", "4KS54KSw4KS+4KSu4KSc4KS84KS+4KSm4KS+", "4KS54KSw4KS+4KSu4KSc4KS+4KSm4KS+", "4KS54KSw4KS+4KSu4KSc4KS84KS+4KSm4KWH", "4KSX4KS+4KSC4KSh4KWC", "4KSX4KS+4KSC4KSh", "4KSX4KS+4KSB4KSh", "4KSy4KWM4KSh4KS84KS+", "4KSy4KSC4KSh", "4KSa4KWC4KSk", "4KSV4KSu4KWA4KSo4KS+", "4KSV4KSu4KWA4KSo4KWH", "4KSt4KSh4KS84KS14KS+", "4KSV4KWB4KSk4KS/4KSv4KS+", "4KSb4KS/4KSo4KS+4KSy",)},
    "greek": {base64.b64decode(w).decode() for w in ("zrzOsc67zqzOus6xz4I=", "zrzOsc67zqzOus6x", "zrzOsc67zqzOus61z4I=", "z4DOv8+Fz4TOrM69zrE=", "z4DOv8+Fz4TOrM69zrXPgg==", "zrPOsc68z44=", "zrPOsc68zq7Pg86/z4U=", "zrPOsc68zrnPjM67zrc=", "zrrOsc+BzrnPjM67zrc=", "zrrOsc+BzrnPjM67zrfPgg==", "z4DOv8+Nz4PPhM63z4I=", "z4DOv8+Nz4PPhM63", "zrHPgc+Hzq/OtM65", "zrHPgc+Hzq/OtM65zrE=", "zrzOv8+Fzr3Orw==", "z4DOv8+Nz4TPg86x", "z4POus6xz4TOrA==",)},
    "hebrew": {base64.b64decode(w).decode() for w in ("15bXldeg15Q=", "15bXldeg15XXqg==", "16nXqNee15XXmNeU", "16nXqNee15XXmNeV16o=", "157XoNeZ15DXpw==", "157XoNeZ15DXp9eZ150=", "15vXldeh15nXqg==", "15bXmdeV158=", "15zXlteZ15nXnw==", "157XlteT15nXmdef", "15fXqNeQ", "15vXldep15k=",)},
    "ukrainian": {base64.b64decode(w).decode() for w in ("0LrRg9GA0LLQsA==", "0YHRgNCw0LrQsA==", "0YXRg9C50L3Rjw==",)},
    "japanese": {base64.b64decode(w).decode() for w in ("44GP44Gd", "44Gn44G2", "44Gh44KT44GT", "44G+44KT44GT",)},
}


def hiragana(text: str) -> str:
    """Katakana to hiragana, so クソ and くそ are the same word."""
    return "".join(chr(ord(c) - 0x60) if "\u30A1" <= c <= "\u30F6" else c for c in text)

ARABIC_MARKS = re.compile("[\u064B-\u0652\u0670\u0640]")
# Arabic joins small words to the front: و (and), ف, ب (with), ل (for), ال (the).
ARABIC_PREFIXES = ("", "و", "ف", "ب", "ل", "ال", "وال", "بال", "فال", "لل", "ول", "وب")
# Hebrew does the same: ו (and), ה (the), ב (in), ל (to), מ (from), ש (that), כ (as).
HEBREW_PREFIXES = ("", "ו", "ה", "ב", "ל", "מ", "ש", "כ", "וה", "וב", "ול", "שה", "שב", "מה", "כש")
PREFIXES = {"arabic": ARABIC_PREFIXES, "persian": ("",), "hebrew": HEBREW_PREFIXES}

# A letter, or a Devanagari letter or sign (vowel signs are marks, not word characters, to \w).
_L = r"(?:[^\W\d_]|[\u0900-\u0963\u0970-\u097F])"
WORD = re.compile(_L + "+(?:'" + _L + "+)*")


class Blocklist:
    def __init__(self, language: str, cache: pathlib.Path):
        code = CODES[language]
        path = cache / f"ldnoobw-{code}.txt"
        if code is None:
            path = None
        elif not path.exists():
            cache.mkdir(parents=True, exist_ok=True)
            request = urllib.request.Request(URL.format(code=code), headers={"User-Agent": "ductus-corpus-builder"})
            with urllib.request.urlopen(request, timeout=60) as response:
                path.write_bytes(response.read())
            time.sleep(0.5)
        lines = path.read_text(encoding="utf-8").splitlines() if path else []
        terms = {line.strip().lower() for line in lines if line.strip()}
        terms |= EXTRA.get(language, set())
        self.prefixes = PREFIXES.get(language)
        if self.prefixes:
            terms = {ARABIC_MARKS.sub("", t) for t in terms}
        self.kana_fold = language == "japanese"
        if self.kana_fold:
            terms = {hiragana(t) for t in terms}
        self.unspaced = language in UNSPACED
        self.words = {t for t in terms if " " not in t}
        self.phrases = [t for t in terms if " " in t]
        self.long_terms = [t for t in terms if len(t) >= 2]
        self.allow = {hiragana(a) for a in ALLOW.get(language, set())} if self.kana_fold else ALLOW.get(language, set())

    def blocks_word(self, word: str) -> bool:
        word = word.lower().strip(".,?!。、？！")
        if self.kana_fold:
            word = hiragana(word)
        if word in self.allow:
            return False
        if self.prefixes:
            word = ARABIC_MARKS.sub("", word)
            return any(word.startswith(p) and word[len(p):] in self.words for p in self.prefixes)
        if self.unspaced:
            return word in self.words or any(word.startswith(term) for term in self.long_terms)
        return word in self.words

    def blocks_text(self, text: str, chunks: list[str] | None = None) -> bool:
        """For Japanese, Chinese and Korean, pass the sentence's words as `chunks`."""
        if self.unspaced:
            return any(self.blocks_word(chunk) for chunk in (chunks or []))
        lower = text.lower()
        # "l'imbecille" counts as "imbecille" (French and Italian elide with an apostrophe).
        tokens = [part for token in WORD.findall(lower) for part in token.split("'")]
        if self.prefixes:
            if any(self.blocks_word(token) for token in tokens):
                return True
        if any(token in self.words and token not in self.allow for token in tokens):
            return True
        return any(re.search(r"\b" + re.escape(phrase) + r"\b", lower) for phrase in self.phrases)
