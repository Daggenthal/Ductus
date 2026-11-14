# Word list sources

`DuctusEngine/Sources/DuctusEngine/Resources/english-words.tsv` is a word frequency list built by `scripts/build_corpus.py` from these public-domain books, downloaded from [Project Gutenberg](https://www.gutenberg.org):

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

`english-sentences.txt` is a sample of 4,000 sentences from the same books, for sentence drills and races. Only plain sentences are kept: letters, spaces and simple punctuation, 40 to 140 characters, no dialogue quotes, numbers or all-caps words.

The works are public domain in the United States. The Project Gutenberg header and footer (license and trademark text) are stripped before counting, and only word counts and the sentence sample are shipped, not the full texts.

To rebuild:

```sh
python3 scripts/build_corpus.py --cache /path/to/download/folder
```
