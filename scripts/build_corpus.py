#!/usr/bin/env python3
"""Build Ductus's English word frequency list from public-domain books.

Downloads plain-text books from Project Gutenberg, strips the Gutenberg
header and footer (the license text is not part of the public-domain work),
counts lowercase words, drops proper nouns, and writes `word<TAB>count`
lines sorted by count.

Usage:
    python3 scripts/build_corpus.py --cache <download dir> [--out <path>]

The output is checked into the repo, so this only needs to run when the
book list or filters change. See CORPUS.md for the source list.
"""

import argparse
import collections
import pathlib
import re
import sys
import time
import urllib.request

# Project Gutenberg ebook IDs. All public domain in the US.
BOOKS = {
    1342: "Pride and Prejudice, Jane Austen",
    1661: "The Adventures of Sherlock Holmes, Arthur Conan Doyle",
    11: "Alice's Adventures in Wonderland, Lewis Carroll",
    84: "Frankenstein, Mary Shelley",
    74: "The Adventures of Tom Sawyer, Mark Twain",
    120: "Treasure Island, Robert Louis Stevenson",
    64317: "The Great Gatsby, F. Scott Fitzgerald",
    345: "Dracula, Bram Stoker",
    35: "The Time Machine, H. G. Wells",
    36: "The War of the Worlds, H. G. Wells",
    514: "Little Women, Louisa May Alcott",
    55: "The Wonderful Wizard of Oz, L. Frank Baum",
    43: "The Strange Case of Dr Jekyll and Mr Hyde, Robert Louis Stevenson",
    174: "The Picture of Dorian Gray, Oscar Wilde",
    2641: "A Room with a View, E. M. Forster",
    45: "Anne of Green Gables, L. M. Montgomery",
    16: "Peter Pan, J. M. Barrie",
    215: "The Call of the Wild, Jack London",
}

URL = "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"
USER_AGENT = "ductus-corpus-builder"

START = re.compile(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*", re.I)
END = re.compile(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG EBOOK", re.I)
TOKEN = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)*")

MAX_WORDS = 10_000
MIN_COUNT = 3
MAX_LENGTH = 12
# A word must appear in lowercase at least this share of the time,
# otherwise it is treated as a proper noun ("Holmes", "Elizabeth").
MIN_LOWERCASE_SHARE = 0.3
SINGLE_LETTER_WORDS = {"a"}
# Drops fragments like "ll" (from "we'll" split by odd quoting) and "hm".
VOWEL = re.compile(r"[aeiouy]")


def fetch(book_id: int, cache: pathlib.Path) -> str:
    path = cache / f"pg{book_id}.txt"
    if not path.exists():
        request = urllib.request.Request(URL.format(id=book_id), headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            path.write_bytes(response.read())
        time.sleep(1)  # be polite to gutenberg.org
    return path.read_text(encoding="utf-8-sig", errors="replace")


def strip_gutenberg(text: str, book_id: int) -> str:
    start = START.search(text)
    end = END.search(text)
    if not start or not end:
        raise ValueError(f"book {book_id}: Gutenberg start/end markers not found")
    return text[start.end():end.start()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache", required=True, type=pathlib.Path, help="folder for downloaded books")
    parser.add_argument("--out", type=pathlib.Path,
                        default=pathlib.Path("DuctusEngine/Sources/DuctusEngine/Resources/english-words.tsv"))
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)

    total = collections.Counter()
    lowercase = collections.Counter()

    for book_id, title in BOOKS.items():
        body = strip_gutenberg(fetch(book_id, args.cache), book_id)
        body = body.replace("’", "'").replace("‘", "'")
        for token in TOKEN.findall(body):
            if "'" in token:
                continue  # contractions and possessives are skipped for now
            word = token.lower()
            total[word] += 1
            if token == word:
                lowercase[word] += 1
        print(f"ok  {book_id:>6}  {title}", file=sys.stderr)

    kept = [
        (word, count) for word, count in total.items()
        if count >= MIN_COUNT
        and len(word) <= MAX_LENGTH
        and (len(word) > 1 or word in SINGLE_LETTER_WORDS)
        and VOWEL.search(word)
        and lowercase[word] / count >= MIN_LOWERCASE_SHARE
    ]
    kept.sort(key=lambda item: (-item[1], item[0]))
    kept = kept[:MAX_WORDS]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        for word, count in kept:
            f.write(f"{word}\t{count}\n")
    print(f"wrote {len(kept)} words to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
