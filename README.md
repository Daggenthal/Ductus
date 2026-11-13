# Ductus

A free, open source typing tutor for macOS, built for learning alternative keyboard layouts like Dvorak and Colemak.

Ductus adapts drills to your weak keys in real time and shows a transparent on-screen keyboard that lights up keys as you press them. Everything runs locally: No accounts, no telemetry.

The name comes from calligraphy: The ductus is the order, direction and rhythm of the strokes that form a letter. That is muscle memory, which is what this app trains.

## Status

Early development. Right now the repo has the core engine (keystroke logging, per-key and per-bigram speed and accuracy stats) with tests. The app itself comes next.

## Layout

```
DuctusEngine/          Swift package, no UI imports
  Sources/DuctusEngine Keystroke log, rolling stats, session tracking
  Sources/DuctusLog    Colored terminal logger
  Tests/               Swift Testing suites
```

## Building and testing

Requires Xcode 16 or newer (Swift 6).

```sh
cd DuctusEngine
swift test
```

## Debugging

- `DUCTUS_DEBUG=1` turns on debug logging.
- `DUCTUS_NO_COLOR=1` (or `NO_COLOR=1`) turns off colored log output.

## License

MIT. See [LICENSE](LICENSE).
