# Word list sources

Each language has a word frequency list (`<language>-words.tsv`) and a sample of up to 4,000 sentences (`<language>-sentences.txt`) in `DuctusEngine/Sources/DuctusEngine/Resources/`. They are built by `scripts/build_corpus.py` from public-domain books downloaded from [Project Gutenberg](https://www.gutenberg.org).

The works are public domain in the United States. The Project Gutenberg header and footer (license and trademark text) are stripped before counting, and only word counts and the sentence samples are shipped, not the full texts.

## How the lists are cleaned

- Swear words and slurs are left out of the word lists, and sentences containing them are dropped, in every language. The terms come from the [List of Dirty, Naughty, Obscene, and Otherwise Bad Words](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) (LDNOOBW, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), downloaded when building and not shipped with the app. `scripts/blocklist.py` keeps a short allow-list of everyday words those lists also flag (Portuguese "comer", Italian "pesce", Japanese 成功, ...) and a few extra spellings. Spaced languages match whole words; Japanese, Chinese and Korean are checked word by word, with katakana and hiragana treated as the same.

- Proper nouns are dropped: a word must be lowercase at least 30% of the time. German keeps nouns capitalized when they appear capitalized in at least 5 different books (names usually appear in one or two).
- Elided words count as the word itself: "l'homme" counts as "homme" (French, Italian, Portuguese, Dutch).
- Old spellings are mapped to modern ones where the change is simple (Spanish "fué" to "fue", German "daß" to "dass", Italian "perchè" to "perché"), and dropped otherwise.
- Outside English, a word must appear in at least 2 books and pass the macOS spell checker for its language. That drops old spellings (Portuguese "fôrça", Dutch "eenigszins"), typos and foreign words. The spell checker only filters; every word comes from the books. This step needs macOS.
- Accented letters used very rarely in a language (like "á" in Dutch "háár") are dropped with their words, so they never join the unlock order. Plain a to z letters are always kept.
- Sentences are plain prose: letters, spaces and simple punctuation, 40 to 140 characters, no dialogue quotes, numbers or all-caps words. Spanish sentences keep their ¿ and ¡.

Non-English books are prose fiction by authors born in 1830 or later, so spelling is close to modern, one book per author, picked from the Gutenberg catalog.

## English

| ID | Title |
|---|---|
| 1342 | Pride and Prejudice, Jane Austen |
| 1661 | The Adventures of Sherlock Holmes, Arthur Conan Doyle |
| 11 | Alice's Adventures in Wonderland, Lewis Carroll |
| 84 | Frankenstein, Mary Shelley |
| 74 | The Adventures of Tom Sawyer, Mark Twain |
| 120 | Treasure Island, Robert Louis Stevenson |
| 64317 | The Great Gatsby, F. Scott Fitzgerald |
| 345 | Dracula, Bram Stoker |
| 35 | The Time Machine, H. G. Wells |
| 36 | The War of the Worlds, H. G. Wells |
| 514 | Little Women, Louisa May Alcott |
| 55 | The Wonderful Wizard of Oz, L. Frank Baum |
| 43 | The Strange Case of Dr Jekyll and Mr Hyde, Robert Louis Stevenson |
| 174 | The Picture of Dorian Gray, Oscar Wilde |
| 2641 | A Room with a View, E. M. Forster |
| 45 | Anne of Green Gables, L. M. Montgomery |
| 16 | Peter Pan, J. M. Barrie |
| 215 | The Call of the Wild, Jack London |

## French

| ID | Title |
|---|---|
| 60383 | Le Diable au corps, Raymond Radiguet |
| 70117 | Mon corps et moi, René Crevel |
| 55637 | Les aventures de Télémaque, Louis Aragon |
| 71236 | Maïténa, Bernard Nabonne |
| 72808 | L'homme couvert de femmes, Pierre Drieu La Rochelle |
| 77967 | Le trois-mâts fantôme, Frédéric Causse |
| 64990 | Le Chèvrefeuille, Thierry Sandre |
| 66845 | La Guerre est morte, Louis Delluc |
| 68606 | Le Maître du navire, Louis Chadourne |
| 59889 | Thomas l'imposteur, Jean Cocteau |
| 69437 | Prodige du cœur, Charles Silvestre |
| 71926 | Rabevel, volume 1, Lucien Fabre |
| 66674 | La vivante paix, Paule Régnier |
| 71272 | Sous le soleil de Satan, Georges Bernanos |
| 50447 | Un tel de l'armée française, Gabriel Tristan Franconi |
| 72954 | Le braconnier de la mer, Jean Mauclère |
| 74863 | Calixte, Jean Dufourt |
| 5781 | Le grand Meaulnes, Alain-Fournier |
| 11046 | La vie d'Ernest Psichari, Henri Massis |
| 14399 | Ce que disait la flamme, Hector Bernier |

## Spanish

| ID | Title |
|---|---|
| 79074 | Narraciones maravillosas y biografías ejemplares, Manuel Chaves Nogales |
| 62986 | Tres relatos porteños, Arturo Cancela |
| 63228 | La quinta de Palmyra, Ramón Gómez de la Serna |
| 78630 | Locura y muerte de Nadie, Benjamín Jarnés |
| 28592 | El pecado y la noche, Antonio de Hoyos y Vinent |
| 58865 | Volvoreta, Wenceslao Fernández Flórez |
| 57448 | Meditaciones del Quijote, José Ortega y Gasset |
| 59631 | La Casa de los Cuervos, Hugo Wast |
| 77334 | El proceso, Franz Kafka |
| 60748 | Nacha Regules, Manuel Gálvez |
| 23239 | La copa de Verlaine, Emilio Carrere |
| 14318 | Belarmino y Apolonio, Ramón Pérez de Ayala |
| 26545 | Antonio Azorín, Azorín |
| 13507 | Cuentos de amor de locura y de muerte, Horacio Quiroga |
| 44309 | Escuela de humorismo, Guillermo Díaz-Caneja |
| 26771 | Thespis, Carlos Octavio Bunge |
| 29920 | La gloria de don Ramiro, Enrique Larreta |
| 73105 | Ganarás el pan, Pedro Mata |
| 60376 | Cuentos de poeta, Rufino Blanco-Fombona |
| 65689 | Las fuerzas extrañas, Leopoldo Lugones |

## German

| ID | Title |
|---|---|
| 76661 | Zu stark für dies Leben, Iwan Heilbut |
| 49992 | Die Ströme des Namenlos, Emma Waiblinger |
| 32814 | Sekunde durch Hirn, Melchior Vischer |
| 46551 | Das zerstörte Idyll, Hans Flesch-Brunningen |
| 62801 | Die Vergiftung, Maria Lazar |
| 66452 | Die Liebe, Hans Kaltneker |
| 7985 | Zur freundlichen Erinnerung, Oskar Maria Graf |
| 39126 | Der Rebell, Manfred George |
| 52327 | Die Gnadenwahl, Hans Arthur Thies |
| 76308 | Fetzen, Alexander Weicker |
| 40222 | Klagen eines Knaben, Carl Ehrenstein |
| 52486 | Adelina, Bohuslav Kokoschka |
| 37436 | Verfall und Triumph, zweiter Teil, Johannes R. Becher |
| 38505 | Der gläserne Garten, Claire Goll |
| 52295 | Auch ich, auch du, Hans Siemsen |
| 76321 | Der wilde Garten, Grete von Urbanitzky |
| 30628 | Das rasende Leben, Kasimir Edschmid |
| 47939 | Nicht der Mörder, der Ermordete ist schuldig, Franz Werfel |
| 63643 | Die Krankheit, Klabund |
| 64133 | Die irdische Unsterblichkeit, Werner Jansen |

## Italian

| ID | Title |
|---|---|
| 41281 | Il perduto amore, Umberto Fracchia |
| 48801 | Il Re bello, Aldo Palazzeschi |
| 40917 | Storie da ridere e da piangere, Ercole Luigi Morselli |
| 36326 | Sciogli la treccia, Maria Maddalena, Guido da Verona |
| 48727 | Le ore inutili, Amalia Guglielminetti |
| 44763 | Gli animali alla guerra, Giulio Caprin |
| 52744 | Il trampolino per le stelle, Lucio D'Ambra |
| 51624 | Dallo Stelvio al mare, Massimo Bontempelli |
| 29035 | L'alcòva d'acciaio, F. T. Marinetti |
| 47786 | Una donna, Sibilla Aleramo |
| 53350 | Il Falco, Alessandro Varaldo |
| 59687 | Mar sanguigno, Guido Milanesi |
| 49837 | Ahi, Giacometta, la tua ghirlandella!, Antonio Beltramelli |
| 43226 | Dopo il divorzio, Grazia Deledda |
| 73083 | Fra i due mondi, Guglielmo Ferrero |
| 25175 | I sogni dell'anarchico, Ugo Mioni |
| 73587 | La prima donna, Ferdinando Di Giorgi |
| 11724 | Roberta, Luciano Zùccoli |
| 28993 | L'immorale, Enrico Annibale Butti |
| 48398 | La patria lontana, Enrico Corradini |

## Portuguese

| ID | Title |
|---|---|
| 23879 | A engomadeira, José de Almada Negreiros |
| 68807 | A confissão de Lúcio, Mário de Sá-Carneiro |
| 71745 | Crónicas imorais, Albino Forjaz de Sampaio |
| 34039 | Aquela família, Ladislau Patrício |
| 67535 | Triste fim de Policarpo Quaresma, Lima Barreto |
| 30413 | Mundanismos, Almachio Diniz |
| 32020 | Serão inquieto, António Patrício |
| 26371 | Nova Safo, Visconde de Vila-Moura |
| 35073 | Flirts, Henrique de Vasconcelos |
| 46860 | O Napoleão de Notting Hill, G. K. Chesterton |
| 23687 | A morte vence, João Grave |
| 27155 | Infelizes, Ana de Castro Osório |
| 21290 | Os bravos do Mindelo, Faustino da Fonseca |
| 20841 | Os pobres, Raul Brandão |
| 24190 | No país dos Yankees, Adolfo Caminha |
| 28691 | Contos do Norte, João Marques de Carvalho |
| 34750 | Mistério do Natal, Coelho Neto |
| 68541 | O Ateneu, Raul Pompeia |
| 34963 | Ao de leve, Brito Camacho |
| 67594 | A intrusa, Júlia Lopes de Almeida |

## Dutch

| ID | Title |
|---|---|
| 33297 | Van aardappelmes tot officiersdegen, Melis Stoke |
| 66931 | Uit de schooljaren van Hans Doncker, Fred. Berens |
| 11355 | Pallieter, Felix Timmermans |
| 12008 | Geerten Basse, Lode Monteyne |
| 76779 | Malle gevallen, Hans Martin |
| 29044 | Een meisje-studentje, Annie Salomons |
| 41240 | Kinderen uit m'n klas, P. J. Cohen de Vries |
| 24115 | Onder den rook der mijn, Felix Rutten |
| 42262 | Piepkuikentje, Anna van Beusekom |
| 15083 | Jerusalem, Jacob Israël de Haan |
| 29719 | Dichtertje, De uitvreter, Titaantjes, Nescio |
| 69157 | Lord Lister 376, Theo von Blankensee |
| 71423 | Een Indisch huwelijk, Carry van Bruggen |
| 76762 | Tuintjes, C. M. van Hille-Gaerthé |
| 12070 | Een jolig troepje, Marie Leopold |
| 58563 | De vlegeljaren van Pietje Bell, Chr. van Abkoude |
| 15048 | Mijnheer Snepvangers, Lode Baekelmans |
| 16841 | Johan Doxa, Herman Teirlinck |
| 45017 | Het boek van Siman den Javaan, E. F. E. Douwes Dekker |

## Japanese, Chinese and Korean

These are typed the way you would type into a macOS input method, with the native text shown above: Japanese as kana-faithful romaji ("toukyou", "watashiha"), Chinese as toneless pinyin with v for ü ("zhongwen", "lv"), Korean as the 2-Set (Dubeolsik) jamo keys you press ("ㅇㅏㄴㄴㅕㅇ" for 안녕; compound vowels and final consonant pairs are two keys, so 와 is ㅇㅗㅏ).

- **Source:** sentences from [Tatoeba](https://tatoeba.org), licensed [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/). Word counts use all Japanese (jpn), Mandarin (cmn) and Korean (kor) sentences. Up to 20,000 sentences are shipped per language, only ones with a named author, and each one's Tatoeba ID and author are listed in `japanese-credits.tsv`, `chinese-credits.tsv` and `korean-credits.tsv` (also shown in Settings under Text Sources).
- **Changes made:** Japanese and Chinese sentences are romanized and split into typing chunks (a word with its particles), full-width punctuation becomes the key you type for it, and Chinese is converted to Simplified. Korean sentences are paired with the 2-Set keys for each word. Korean words built on Tatoeba's stock example names (톰, 메리) are left out of the word list.
- **Tools, used only when building the lists (not shipped):** [fugashi](https://github.com/polm/fugashi) (MIT) with [unidic-lite](https://github.com/polm/unidic-lite) (MIT, UniDic BSD) for Japanese words and readings, [jieba](https://github.com/fxsjy/jieba) (MIT) for Chinese words, [pypinyin](https://github.com/mozillazg/python-pinyin) (MIT) for pinyin, and [opencc-python-reimplemented](https://github.com/yichen0831/opencc-python) (Apache 2.0) for Simplified Chinese.
- **Filters:** names, numbers and symbols are left out of the word lists. Japanese verbs and adjectives appear in dictionary form ("okiru", not the stem "oki"). Sentences have 20 to 120 typed characters and only Japanese or Chinese script and punctuation.

## Turkish, Polish, Czech, Hungarian, Greek, Russian, Ukrainian, Hebrew, Arabic, Persian and Hindi

These are typed as written, so the words and sentences are used as they are.

- **Source:** sentences from [Tatoeba](https://tatoeba.org), licensed [CC BY 2.0 FR](https://creativecommons.org/licenses/by/2.0/fr/): Turkish (tur), Polish (pol), Czech (ces), Hungarian (hun), Greek (ell), Russian (rus), Ukrainian (ukr), Hebrew (heb), Persian (pes), Hindi (hin), and for Arabic both Modern Standard Arabic (ara) and Egyptian Arabic (arz). Up to 20,000 sentences with a named author are shipped per language, each credited in that language's `-credits.tsv` file.
- **Changes made:** Arabic and Persian short vowel marks (harakat), shadda, sukun and tatweel are removed, and Hebrew niqqud, since everyday text is written and typed without them. Persian uses the Persian ی and ک where a sentence has the Arabic forms. The Greek question mark (;) is kept as the semicolon key that types it. Hindi is normalized (NFC), so nukta letters like क़ are stored as क plus ़, the two keys that type them. Hindi keeps words used only once, since Tatoeba has fewer Hindi sentences.
- **Filters:** Words written mostly with a capital are names and are left out (Turkish is lowercased with its own rules, I to ı and İ to i). Arabic, Persian and Hebrew have no capitals, so Tatoeba's stock example names (Sami, Layla, Tom, Mary and a few more) are left out of those word lists by hand. Turkish words with an apostrophe (Tom'un) appear in sentences only. Single letters are kept only when they are real words (Russian в, Polish w, Arabic و, Greek η); the rest are initials or abbreviations. Ukrainian words with an apostrophe (м'ясо) appear in sentences only. Swear words use the LDNOOBW Russian list for both Russian and Ukrainian, plus a few Ukrainian additions. LDNOOBW has no Greek or Hebrew list, and its Hindi list is in Latin letters, so `blocklist.py` has a short list for each of those. Arabic and Hebrew words are also checked with their attached prefixes removed (Arabic و ف ب ل ال, Hebrew ו ה ב ל מ ש כ).

Japanese public-domain books from [Aozora Bunko](https://www.aozora.gr.jp) could be added later; their out-of-copyright texts may be freely copied and redistributed.

## Study word sets (HSK)

- **Source:** [complete-hsk-vocabulary](https://github.com/drkameleon/complete-hsk-vocabulary) by Yanis Zafirópulos (MIT), levels from the revised HSK 3.0 syllabus (November 2025; HSK 1 is about 300 words). Its English meanings come from [CC-CEDICT](https://cc-cedict.org/wiki/) under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), so the meanings in `study-hsk1.tsv` to `study-hsk7.tsv` stay under that license (the rest of Ductus is MIT).
- **Changes made:** One reading per word. Words with several readings get the everyday one: surnames, old variants and "used in" entries are skipped, and a few are set by hand (吗 ma, 喝 hē, 雨 yǔ). At most three meanings are kept. The typed form is toneless pinyin with v for ü.
- **Rebuilding:** `python3 scripts/build_study.py --source /path/to/complete.json`

## Rebuilding

```sh
python3 scripts/build_corpus.py --cache /path/to/download/folder
# Russian, Ukrainian, Arabic, Japanese, Chinese and Korean (see the script header for the Tatoeba downloads):
pip install fugashi unidic-lite jieba pypinyin opencc-python-reimplemented
python3 scripts/build_cjk_corpus.py --tatoeba /path/to/tatoeba/exports
# or only some languages:
python3 scripts/build_corpus.py --cache /path/to/download/folder --languages french,german
```
