# Ductus

A free, open source typing tutor for macOS, built for learning alternative keyboard layouts like Dvorak and Colemak.

Ductus adapts drills to your weak keys in real time and shows a transparent on-screen keyboard that lights up keys as you press them. Everything runs locally: No accounts, no telemetry.

The name comes from calligraphy: The ductus is the order, direction and rhythm of the strokes that form a letter. That is muscle memory, which is what this app trains.

## Status

Early development. Right now the repo has the core engine with tests:

- Keystroke logging with per-key and per-bigram speed and accuracy stats.
- Drills made of real English words, weighted toward your weakest keys. Each session starts with a short warm-up on keys you have mastered.
- Progressive unlocking: Start on your layout's home row, unlock the next letter once every current key hits the target speed and accuracy (35 WPM and 95% by default).

The Mac app has:

- Practice, Race and History tabs. Races are timed (30s to 5 min) against your own best, with all letters, unlocked letters only, or real sentences.
- An on-screen keyboard (ANSI, ISO or JIS) that follows your active layout, docked or floating, with a configurable ⌘ shortcut glow. It fades keys you have mastered, and can light up while you type in other apps (opt-in, needs Input Monitoring).
- Options for unlock targets, stop-on-mistake or fix-with-Backspace, capitals, punctuation, sentence drills, text size, a daily goal and key sounds.
- Saved progress per layout, history with charts, a weak-key heatmap, and CSV export.

## Layout

```
DuctusEngine/          Swift package, no UI imports
  Sources/DuctusEngine Stats, unlocking, drill generation, bundled word list
  Sources/DuctusLog    Colored terminal logger
  Sources/ductus-demo  Simulated learner, shows drills adapting
  Tests/               Swift Testing suites
scripts/
  build_corpus.py      Builds the word list from public-domain books
```

The word list comes from public-domain books on Project Gutenberg. See [CORPUS.md](CORPUS.md).

## Building and testing

Requires Xcode 16 or newer (Swift 6) and macOS 14 or newer.

Open `Ductus.xcodeproj` and run the Ductus scheme, or from the terminal:

```sh
xcodebuild -project Ductus.xcodeproj -scheme Ductus build
```

The engine has its own tests and demo:

```sh
cd DuctusEngine
swift test
swift run ductus-demo            # watch a simulated learner progress (add --qwerty to compare)
```

## Debugging

- `DUCTUS_DEBUG=1` turns on debug logging.
- `DUCTUS_NO_COLOR=1` (or `NO_COLOR=1`) turns off colored log output.

## License

MIT. See [LICENSE](LICENSE).
