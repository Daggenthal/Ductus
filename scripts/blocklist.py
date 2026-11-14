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
    "arabic": "ar", "russian": "ru",
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
}

# Additions to LDNOOBW for words it misses.
EXTRA = {
    # Base64 so the words do not show up when reading the repo. Kana folding
    # covers the katakana spellings too.
    "ukrainian": {base64.b64decode(w).decode() for w in ("0LrRg9GA0LLQsA==", "0YHRgNCw0LrQsA==", "0YXRg9C50L3Rjw==",)},
    "japanese": {base64.b64decode(w).decode() for w in ("44GP44Gd", "44Gn44G2", "44Gh44KT44GT", "44G+44KT44GT",)},
}


def hiragana(text: str) -> str:
    """Katakana to hiragana, so クソ and くそ are the same word."""
    return "".join(chr(ord(c) - 0x60) if "\u30A1" <= c <= "\u30F6" else c for c in text)

ARABIC_MARKS = re.compile("[\u064B-\u0652\u0670\u0640]")
# Arabic joins small words to the front: و (and), ف, ب (with), ل (for), ال (the).
ARABIC_PREFIXES = ("", "و", "ف", "ب", "ل", "ال", "وال", "بال", "فال", "لل", "ول", "وب")

WORD = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*")


class Blocklist:
    def __init__(self, language: str, cache: pathlib.Path):
        code = CODES[language]
        path = cache / f"ldnoobw-{code}.txt"
        if not path.exists():
            cache.mkdir(parents=True, exist_ok=True)
            request = urllib.request.Request(URL.format(code=code), headers={"User-Agent": "ductus-corpus-builder"})
            with urllib.request.urlopen(request, timeout=60) as response:
                path.write_bytes(response.read())
            time.sleep(0.5)
        terms = {line.strip().lower() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}
        terms |= EXTRA.get(language, set())
        self.arabic = language == "arabic"
        if self.arabic:
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
        if self.arabic:
            word = ARABIC_MARKS.sub("", word)
            return any(word.startswith(p) and word[len(p):] in self.words for p in ARABIC_PREFIXES)
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
        if self.arabic:
            return any(self.blocks_word(token) for token in tokens)
        if any(token in self.words and token not in self.allow for token in tokens):
            return True
        return any(re.search(r"\b" + re.escape(phrase) + r"\b", lower) for phrase in self.phrases)
