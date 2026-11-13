# Ductus

A free, open source typing tutor for macOS, built for learning alternative keyboard layouts like Dvorak and Colemak.

Ductus adapts drills to your weak keys in real time and shows a transparent on-screen keyboard that lights up keys as you press them. Everything runs locally: No accounts, no telemetry.

The name comes from calligraphy: The ductus is the order, direction and rhythm of the strokes that form a letter. That is muscle memory, which is what this app trains.

## Status

Early development. Right now the repo has the core engine with tests:

- Keystroke logging with per-key and per-bigram speed and accuracy stats.
- Drills made of real English words, weighted toward your weakest keys.
- Progressive unlocking: Start on your layout's home row, unlock the next letter once every current key hits the target speed and accuracy (35 WPM and 95% by default).

The app itself comes next.

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
