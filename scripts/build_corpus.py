#!/usr/bin/env python3
"""Build Ductus's word frequency lists and sentence samples from public-domain books.

For each language: downloads plain-text books from Project Gutenberg, strips
the Gutenberg header and footer (the license text is not part of the
public-domain work), counts words, drops proper nouns and old spellings, and
writes `word<TAB>count` lines sorted by count. Also writes a sample of clean
sentences, one per line, for sentence drills and races.

Usage:
    python3 scripts/build_corpus.py --cache <download dir> [--languages english,french,...]

Outputs go to DuctusEngine/Sources/DuctusEngine/Resources/<language>-words.tsv
and <language>-sentences.txt. They are checked into the repo, so this only
needs to run when the book lists or filters change. See CORPUS.md.
"""

import argparse
import collections
import pathlib
import random
import re
import subprocess
import sys
import time
import urllib.request

RESOURCES = pathlib.Path("DuctusEngine/Sources/DuctusEngine/Resources")
URL = "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"
USER_AGENT = "ductus-corpus-builder"

START = re.compile(r"\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*", re.I)
END = re.compile(r"\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG EBOOK", re.I)

MAX_WORDS = 10_000
MIN_COUNT = 3
MAX_LENGTH = 12
# A word must appear in lowercase at least this share of the time,
# otherwise it is treated as a proper noun ("Holmes", "Elizabeth").
MIN_LOWERCASE_SHARE = 0.3
MAX_SENTENCES = 4000

# Project Gutenberg ebook IDs. All public domain in the US. Non-English books
# are prose fiction by authors born 1830 or later (so spelling is close to
# modern), one book per author, chosen from the Gutenberg catalog.
BOOKS = {
    "english": {
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
    },
    "french": {
        60383: "Le Diable au corps, Raymond Radiguet",
        70117: "Mon corps et moi, René Crevel",
        55637: "Les aventures de Télémaque, Louis Aragon",
        71236: "Maïténa, Bernard Nabonne",
        72808: "L'homme couvert de femmes, Pierre Drieu La Rochelle",
        77967: "Le trois-mâts fantôme, Frédéric Causse",
        64990: "Le Chèvrefeuille, Thierry Sandre",
        66845: "La Guerre est morte, Louis Delluc",
        68606: "Le Maître du navire, Louis Chadourne",
        59889: "Thomas l'imposteur, Jean Cocteau",
        69437: "Prodige du cœur, Charles Silvestre",
        71926: "Rabevel, volume 1, Lucien Fabre",
        66674: "La vivante paix, Paule Régnier",
        71272: "Sous le soleil de Satan, Georges Bernanos",
        50447: "Un tel de l'armée française, Gabriel Tristan Franconi",
        72954: "Le braconnier de la mer, Jean Mauclère",
        74863: "Calixte, Jean Dufourt",
        5781: "Le grand Meaulnes, Alain-Fournier",
        11046: "La vie d'Ernest Psichari, Henri Massis",
        14399: "Ce que disait la flamme, Hector Bernier",
    },
    "spanish": {
        79074: "Narraciones maravillosas y biografías ejemplares, Manuel Chaves Nogales",
        62986: "Tres relatos porteños, Arturo Cancela",
        63228: "La quinta de Palmyra, Ramón Gómez de la Serna",
        78630: "Locura y muerte de Nadie, Benjamín Jarnés",
        28592: "El pecado y la noche, Antonio de Hoyos y Vinent",
        58865: "Volvoreta, Wenceslao Fernández Flórez",
        57448: "Meditaciones del Quijote, José Ortega y Gasset",
        59631: "La Casa de los Cuervos, Hugo Wast",
        77334: "El proceso, Franz Kafka",
        60748: "Nacha Regules, Manuel Gálvez",
        23239: "La copa de Verlaine, Emilio Carrere",
        14318: "Belarmino y Apolonio, Ramón Pérez de Ayala",
        26545: "Antonio Azorín, Azorín",
        13507: "Cuentos de amor de locura y de muerte, Horacio Quiroga",
        44309: "Escuela de humorismo, Guillermo Díaz-Caneja",
        26771: "Thespis, Carlos Octavio Bunge",
        29920: "La gloria de don Ramiro, Enrique Larreta",
        73105: "Ganarás el pan, Pedro Mata",
        60376: "Cuentos de poeta, Rufino Blanco-Fombona",
        65689: "Las fuerzas extrañas, Leopoldo Lugones",
    },
    "german": {
        76661: "Zu stark für dies Leben, Iwan Heilbut",
        49992: "Die Ströme des Namenlos, Emma Waiblinger",
        32814: "Sekunde durch Hirn, Melchior Vischer",
        46551: "Das zerstörte Idyll, Hans Flesch-Brunningen",
        62801: "Die Vergiftung, Maria Lazar",
        66452: "Die Liebe, Hans Kaltneker",
        7985: "Zur freundlichen Erinnerung, Oskar Maria Graf",
        39126: "Der Rebell, Manfred George",
        52327: "Die Gnadenwahl, Hans Arthur Thies",
        76308: "Fetzen, Alexander Weicker",
        40222: "Klagen eines Knaben, Carl Ehrenstein",
        52486: "Adelina, Bohuslav Kokoschka",
        37436: "Verfall und Triumph, zweiter Teil, Johannes R. Becher",
        38505: "Der gläserne Garten, Claire Goll",
        52295: "Auch ich, auch du, Hans Siemsen",
        76321: "Der wilde Garten, Grete von Urbanitzky",
        30628: "Das rasende Leben, Kasimir Edschmid",
        47939: "Nicht der Mörder, der Ermordete ist schuldig, Franz Werfel",
        63643: "Die Krankheit, Klabund",
        64133: "Die irdische Unsterblichkeit, Werner Jansen",
    },
    "italian": {
        41281: "Il perduto amore, Umberto Fracchia",
        48801: "Il Re bello, Aldo Palazzeschi",
        40917: "Storie da ridere e da piangere, Ercole Luigi Morselli",
        36326: "Sciogli la treccia, Maria Maddalena, Guido da Verona",
        48727: "Le ore inutili, Amalia Guglielminetti",
        44763: "Gli animali alla guerra, Giulio Caprin",
        52744: "Il trampolino per le stelle, Lucio D'Ambra",
        51624: "Dallo Stelvio al mare, Massimo Bontempelli",
        29035: "L'alcòva d'acciaio, F. T. Marinetti",
        47786: "Una donna, Sibilla Aleramo",
        53350: "Il Falco, Alessandro Varaldo",
        59687: "Mar sanguigno, Guido Milanesi",
        49837: "Ahi, Giacometta, la tua ghirlandella!, Antonio Beltramelli",
        43226: "Dopo il divorzio, Grazia Deledda",
        73083: "Fra i due mondi, Guglielmo Ferrero",
        25175: "I sogni dell'anarchico, Ugo Mioni",
        73587: "La prima donna, Ferdinando Di Giorgi",
        11724: "Roberta, Luciano Zùccoli",
        28993: "L'immorale, Enrico Annibale Butti",
        48398: "La patria lontana, Enrico Corradini",
    },
    "portuguese": {
        23879: "A engomadeira, José de Almada Negreiros",
        68807: "A confissão de Lúcio, Mário de Sá-Carneiro",
        71745: "Crónicas imorais, Albino Forjaz de Sampaio",
        34039: "Aquela família, Ladislau Patrício",
        67535: "Triste fim de Policarpo Quaresma, Lima Barreto",
        30413: "Mundanismos, Almachio Diniz",
        32020: "Serão inquieto, António Patrício",
        26371: "Nova Safo, Visconde de Vila-Moura",
        35073: "Flirts, Henrique de Vasconcelos",
        46860: "O Napoleão de Notting Hill, G. K. Chesterton",
        23687: "A morte vence, João Grave",
        27155: "Infelizes, Ana de Castro Osório",
        21290: "Os bravos do Mindelo, Faustino da Fonseca",
        20841: "Os pobres, Raul Brandão",
        24190: "No país dos Yankees, Adolfo Caminha",
        28691: "Contos do Norte, João Marques de Carvalho",
        34750: "Mistério do Natal, Coelho Neto",
        68541: "O Ateneu, Raul Pompeia",
        34963: "Ao de leve, Brito Camacho",
        67594: "A intrusa, Júlia Lopes de Almeida",
    },
    "dutch": {
        33297: "Van aardappelmes tot officiersdegen, Melis Stoke",
        66931: "Uit de schooljaren van Hans Doncker, Fred. Berens",
        11355: "Pallieter, Felix Timmermans",
        12008: "Geerten Basse, Lode Monteyne",
        76779: "Malle gevallen, Hans Martin",
        29044: "Een meisje-studentje, Annie Salomons",
        41240: "Kinderen uit m'n klas, P. J. Cohen de Vries",
        24115: "Onder den rook der mijn, Felix Rutten",
        42262: "Piepkuikentje, Anna van Beusekom",
        15083: "Jerusalem, Jacob Israël de Haan",
        29719: "Dichtertje, De uitvreter, Titaantjes, Nescio",
        69157: "Lord Lister 376, Theo von Blankensee",
        71423: "Een Indisch huwelijk, Carry van Bruggen",
        76762: "Tuintjes, C. M. van Hille-Gaerthé",
        12070: "Een jolig troepje, Marie Leopold",
        58563: "De vlegeljaren van Pietje Bell, Chr. van Abkoude",
        15048: "Mijnheer Snepvangers, Lode Baekelmans",
        16841: "Johan Doxa, Herman Teirlinck",
        45017: "Het boek van Siman den Javaan, E. F. E. Douwes Dekker",
    },
}

# Words of one letter that are real words.
SINGLE_LETTER_WORDS = {
    "english": {"a"},
    "french": {"a", "à", "y"},
    "spanish": {"a", "y", "o", "e", "u"},
    "german": set(),
    "italian": {"a", "e", "è", "o", "i"},
    "portuguese": {"a", "e", "o", "é", "à"},
    "dutch": set(),
}

# Old spellings mapped to modern ones (lowercase).
MODERN_SPELLING = {
    "spanish": {
        "fué": "fue", "dió": "dio", "vió": "vio", "fuí": "fui", "á": "a", "ó": "o",
        "dí": "di", "ví": "vi", "pié": "pie", "piés": "pies", "fuéramos": "fuéramos",
    },
    "italian": {"nè": "né", "sè": "sé", "perchè": "perché", "poichè": "poiché",
                "benchè": "benché", "affinchè": "affinché", "finchè": "finché", "giacchè": "giacché"},
    "portuguese": {"á": "à"},
    # Pre-1996 "ß" after a short vowel is "ss" today.
    "german": {
        "daß": "dass", "muß": "muss", "mußt": "musst", "mußte": "musste", "mußten": "mussten",
        "müßte": "müsste", "müßten": "müssten", "wußte": "wusste", "wußten": "wussten",
        "wüßte": "wüsste", "gewiß": "gewiss", "läßt": "lässt", "laß": "lass", "faßte": "fasste",
        "faßten": "fassten", "schloß": "schloss", "schluß": "schluss", "fluß": "fluss",
        "kuß": "kuss", "haß": "hass", "biß": "biss", "riß": "riss", "goß": "goss",
        "naß": "nass", "faß": "fass", "roß": "ross", "schuß": "schuss", "bißchen": "bisschen",
        "genuß": "genuss", "entschluß": "entschluss", "einfluß": "einfluss", "vergißt": "vergisst",
        "vergiß": "vergiss", "ißt": "isst", "iß": "iss", "frißt": "frisst", "prozeß": "prozess",
        "beschluß": "beschluss", "anlaß": "anlass", "abschluß": "abschluss", "mißt": "misst",
        "gewißheit": "gewissheit", "küßte": "küsste", "küßten": "küssten", "wäßrig": "wässrig",
        "häßlich": "hässlich", "verläßt": "verlässt", "entließ": "entließ", "paßt": "passt",
        "paßte": "passte", "faßt": "fasst", "begriß": "begriss", "zerriß": "zerriss",
        "verlaß": "verlass", "kenntniß": "kenntnis", "ereigniß": "ereignis", "geheimniß": "geheimnis",
        "bewußt": "bewusst", "bewußtsein": "bewusstsein", "unbewußt": "unbewusst",
        "mißtrauen": "misstrauen", "vermißt": "vermisst", "vermißte": "vermisste", "rißt": "risst",
        "schloßen": "schlossen", "flüßig": "flüssig", "flüßigkeit": "flüssigkeit",
        "gefaßt": "gefasst", "erfaßt": "erfasst", "verlassen": "verlassen", "mußtest": "musstest",
    },
}

# Words dropped as old or archaic spellings (lowercase), by pattern.
OLD_SPELLING = {
    # "Thür", "Theil", "seyn", "studiren".
    "german": re.compile(r"th|ey|[^aeiouhäöü]iren$|[^aeiouhäöü]irt$|niß"),
    # Pre-1911/1943 forms: "pharmacia", "elle", "commum", "Paiz", "mysterio".
    "portuguese": re.compile(r"ph|th|y|k|w|ll|mm|nn|tt|pp|ff|cc[^eiç]|sc[ei]encia"),
    # Pre-1947 forms: "mensch", "groote", "ooren", "eenige".
    "dutch": re.compile(r"(?<!i)sch(e|en|er)?$|(aa|ee|oo|uu)[bcdfgklmnprstvwz](e|en|er|ig|ige|igen)$"),
    # Old forms with j for i ("gioja", "jeri") and foreign letters.
    "italian": re.compile(r"[jkwxy]"),
}
OLD_WORDS = {
    "dutch": {"den", "eene", "eenen", "zoo", "gij", "ge", "mijnen", "zijnen", "haren", "uwen",
              "onzen", "dezen"},
}

# Languages that elide with an apostrophe ("l'homme", "dell'anno"). The part
# after the apostrophe is the word that counts.
ELIDING = {"french", "italian", "portuguese", "dutch"}
# macOS spell checker languages. Words it rejects (old spellings, typos) are
# dropped, and so are sentences containing them. Build on macOS.
SPELL_CHECK = {
    "french": "fr", "spanish": "es", "german": "de", "italian": "it",
    "portuguese": "pt_BR,pt_PT", "dutch": "nl",
}
# Outside English, a word must appear in at least this many books, which
# drops one-book oddities (foreign words, lowercase names, dialect).
MIN_BOOKS = 2
# Accented letters below this share of all letters are not part of the language's
# practice alphabet; words with them are dropped.
MIN_LETTER_SHARE = 0.0002

# German capitalizes nouns: keep them capitalized when they appear in at
# least this many different books (names stay in one or two books).
CAPITALIZED_NOUNS = {"german": 5}

VOWEL = re.compile(r"[aeiouyàâäéèêëîïôöùûüœæáíóúãõ]")
ENGLISH_TOKEN = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)*")
TOKEN = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*")

# Sentences: letters and simple punctuation, sensible length.
ENGLISH_SENTENCE_OK = re.compile(r"^[A-Z][A-Za-z ,.;:!?'-]+[.!?]$")
ENGLISH_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z])")
SENTENCE_OK = re.compile(r"^[¿¡]?[^\W\d_](?:[^\W\d_]|[ ,.;:!?'¿¡-])+[.!?]$")
SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[¿¡]?[^\W\d_])")
ABBREVIATION_END = re.compile(r"\b(Mr|Mrs|Dr|St|Mme|Messrs|Jr|Sr)\.$")


def normalize(text: str) -> str:
    """Typographic characters to ones a keyboard types."""
    for nbsp in (" ", " ", " "):
        text = text.replace(nbsp, " ")
    return text.replace("’", "'").replace("‘", "'").replace("ʼ", "'")


def modernize(token: str, language: str) -> str | None:
    """Modern spelling of `token`, keeping its capitalization, or None if it is an old form."""
    lower = token.lower()
    lower = MODERN_SPELLING.get(language, {}).get(lower, lower)
    pattern = OLD_SPELLING.get(language)
    if (pattern and pattern.search(lower)) or lower in OLD_WORDS.get(language, set()):
        return None
    if token[0].isupper():
        return lower[0].upper() + lower[1:]
    return lower


def words_in(body: str, language: str) -> list[str]:
    """Tokens to count. English keeps its original rules (contractions skipped)."""
    if language == "english":
        return [t for t in ENGLISH_TOKEN.findall(body) if "'" not in t]
    out = []
    for token in TOKEN.findall(body):
        if "'" in token:
            if language not in ELIDING:
                continue
            token = token.split("'")[-1]  # "l'homme" -> "homme"
            if not token:
                continue
        out.append(token)
    return out


def extract_sentences(body: str, language: str) -> list[str]:
    """Clean sentences from a book body. Dialogue (double quotes and dashes),
    numbers, italics markers, shouting and old spellings are dropped rather than repaired."""
    english = language == "english"
    ok = ENGLISH_SENTENCE_OK if english else SENTENCE_OK
    split = ENGLISH_SENTENCE_SPLIT if english else SENTENCE_SPLIT
    found = []
    for paragraph in re.split(r"\n\s*\n", body):
        text = " ".join(paragraph.split())
        text = text.replace("—", " -- ").replace("“", '"').replace("”", '"')
        for sentence in split.split(text):
            sentence = sentence.strip()
            if not 40 <= len(sentence) <= 140:
                continue
            if not ok.match(sentence) or "--" in sentence or "  " in sentence:
                continue
            if ABBREVIATION_END.search(sentence):
                continue
            if any(word.isupper() and len(word) > 1 for word in sentence.split()):
                continue
            if not english:
                first = sentence.lstrip("¿¡")[0]
                last = sentence.split()[-1].rstrip(".")
                if not first.isupper() or (last[:1].isupper() and len(last) <= 3):
                    continue  # "M. Dupont", "Sr. Pérez": a split at an abbreviation
                # Old spellings are fixed where known, otherwise the sentence is dropped.
                modern = []
                for piece in re.split(r"([^\W\d_]+)", sentence):
                    if piece and piece[0].isalpha():
                        new = modernize(piece, language)
                        if new is None:
                            break
                        # Keep the original capitalization, except mapped words.
                        modern.append(new if piece.lower() != new.lower() else piece)
                    else:
                        modern.append(piece)
                else:
                    sentence = "".join(modern)
                    if language == "spanish" and sentence.endswith("?") and "¿" not in sentence:
                        continue  # books sometimes drop the opening mark
                    if language == "spanish" and sentence.endswith("!") and "¡" not in sentence:
                        continue
                    found.append(sentence)
                continue
            found.append(sentence)
    return found


def spell_checked(words: set[str], language: str) -> set[str]:
    """The words the macOS spell checker accepts for `language`."""
    script = pathlib.Path(__file__).with_name("spellcheck.swift")
    result = subprocess.run(
        ["swift", str(script), SPELL_CHECK[language]],
        input="\n".join(sorted(words)), capture_output=True, text=True, check=True,
    )
    return set(result.stdout.split("\n")) - {""}


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


def build(language: str, cache: pathlib.Path) -> None:
    total = collections.Counter()
    lowercase = collections.Counter()
    capitalized_in_books = collections.Counter()
    books_with = collections.Counter()
    sentences: list[str] = []
    noun_books = CAPITALIZED_NOUNS.get(language)

    for book_id, title in BOOKS[language].items():
        body = strip_gutenberg(fetch(book_id, cache), book_id)
        body = normalize(body) if language != "english" else body.replace("’", "'").replace("‘", "'")
        sentences.extend(extract_sentences(body, language))
        seen_capitalized = set()
        seen = set()
        for token in words_in(body, language):
            if language != "english":
                if token.isupper() and len(token) > 1:
                    continue  # shouting or a heading
                token = modernize(token, language)
                if token is None:
                    continue
            word = token.lower()
            seen.add(word)
            total[word] += 1
            if token == word:
                lowercase[word] += 1
            else:
                seen_capitalized.add(word)
        capitalized_in_books.update(seen_capitalized)
        books_with.update(seen)
        print(f"ok  {language:<10} {book_id:>6}  {title}", file=sys.stderr)

    singles = SINGLE_LETTER_WORDS[language]
    kept = []
    for word, count in total.items():
        if count < MIN_COUNT or len(word) > MAX_LENGTH:
            continue
        if len(word) == 1 and word not in singles:
            continue
        if not VOWEL.search(word):
            continue
        if lowercase[word] / count >= MIN_LOWERCASE_SHARE:
            kept.append((word, count))
        elif noun_books and capitalized_in_books[word] >= noun_books:
            kept.append((word[0].upper() + word[1:], count))
    if language != "english":
        kept = [(w, c) for w, c in kept if books_with[w.lower()] >= MIN_BOOKS]
        accepted = spell_checked({w for w, _ in kept}, language)
        kept = [(w, c) for w, c in kept if w in accepted]
        sentence_words = {piece for s in sentences for piece in re.findall(r"[^\W\d_]+", s)}
        accepted_in_sentences = spell_checked(sentence_words, language)
        before = len(sentences)
        sentences = [s for s in sentences
                     if all(piece in accepted_in_sentences for piece in re.findall(r"[^\W\d_]+", s))]
        # Rare letters ("á" in Dutch "háár") would otherwise join the unlock order.
        letters = collections.Counter()
        for w, c in kept:
            for ch in w.lower():
                letters[ch] += c
        all_letters = sum(letters.values())
        rare = {ch for ch, n in letters.items() if n / all_letters < MIN_LETTER_SHARE and not "a" <= ch <= "z"}
        kept = [(w, c) for w, c in kept if not rare & set(w.lower())]
        sentences = [s for s in sentences if not rare & set(s.lower())]
        if rare:
            print(f"dropped rare letters {''.join(sorted(rare))}", file=sys.stderr)
        print(f"spell check kept {len(kept)} words and {len(sentences)} of {before} sentences", file=sys.stderr)
    kept.sort(key=lambda item: (-item[1], item[0]))
    kept = kept[:MAX_WORDS]

    words_out = RESOURCES / f"{language}-words.tsv"
    with words_out.open("w", encoding="utf-8") as f:
        for word, count in kept:
            f.write(f"{word}\t{count}\n")
    print(f"wrote {len(kept)} words to {words_out}", file=sys.stderr)

    unique = sorted(set(sentences))
    sample = random.Random(42).sample(unique, min(MAX_SENTENCES, len(unique)))
    sentences_out = RESOURCES / f"{language}-sentences.txt"
    with sentences_out.open("w", encoding="utf-8") as f:
        for sentence in sample:
            f.write(sentence + "\n")
    print(f"wrote {len(sample)} of {len(unique)} sentences to {sentences_out}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache", required=True, type=pathlib.Path, help="folder for downloaded books")
    parser.add_argument("--languages", default=",".join(BOOKS), help="comma-separated, default all")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    for language in args.languages.split(","):
        if language not in BOOKS:
            print(f"unknown language {language}", file=sys.stderr)
            return 1
        build(language, args.cache)
    return 0


if __name__ == "__main__":
    sys.exit(main())
