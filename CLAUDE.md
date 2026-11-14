# Ductus

Ductus is a free, open source (MIT) typing tutor for macOS, built for learning alternative keyboard layouts like Dvorak and Colemak. It adapts drills to your weak keys in real time and has a transparent, draggable on-screen keyboard that lights up keys as you press them.

The name comes from calligraphy: the ductus is the order, direction and rhythm of the strokes that form a letter. That is muscle memory, which is what this app trains.

## Why it exists

- KeyKey (the best native Mac typing tutor) is closed source and paid. Ductus is the open alternative that can be changed and extended.
- The author is learning Dvorak and uses the built-in "Dvorak - QWERTY ⌘" input source (Dvorak while typing, QWERTY while holding Command). Ductus must handle that layout correctly.

## Decisions already made

- **Platform:** Pure Swift / SwiftUI, native macOS, Apple Silicon first. Linux may come much later. Do NOT design around Linux now, but keep the adaptive engine free of AppKit/SwiftUI imports so it stays portable.
- **License:** MIT. All code in this repo is MIT.
- **Bundle ID:** `dev.daggenthal.ductus`
- **Everything runs locally.** No accounts, no telemetry, no network required for training. The one network use is the update checker (`Ductus/Updates`): it asks the GitHub releases API for the latest version only when the user checks (or once a day if they opt in), and downloads only when they click Download and Install. Ductus is sandboxed and cannot replace itself, so it downloads the release zip, checks it against SHA256SUMS.txt, writes a request file into its container (macOS drops launch arguments from sandboxed apps) and starts the unsandboxed `DuctusUpdater` helper (embedded in Contents/Helpers), then quits. The helper waits for it to quit, verifies bundle ID and signature, clears quarantine, swaps the app (rolling back on failure) and reopens it. No Sparkle (needs signing keys and sandbox XPC exceptions). Ad-hoc signing means Input Monitoring must be re-granted after each update until the app is notarized.
- **Languages:** English, French, Spanish, German, Italian, Portuguese and Dutch, each with its own word list and sentences from public-domain Gutenberg books (see CORPUS.md). The language comes from the input source (`kTISPropertyInputSourceLanguages`) or a Settings override. Progress is saved per layout and language; English uses the plain layout ID so older progress still loads. Typed characters are worked out by Ductus from the layout data (`UCKeyTranslate` with dead-key state), not taken from macOS, so accents like ´ then e work and the HUD can show the dead key, then the letter. Only letters the layout can type join the unlock order. Japanese and Chinese are typed as romaji and toneless pinyin (v for ü) with the native text shown above (`Gloss`, `GlossBar`), built from Tatoeba sentences (CC BY 2.0 FR; every shipped sentence is credited in `<language>-credits.tsv` and in Settings). Detection also reads the active input method, since Japanese and Chinese input methods type through a layout like ABC. Kana typing on the JIS kana layout is not supported. Korean is typed on 2-Set (Dubeolsik) as jamo keys (ㅇㅏㄴㄴㅕㅇ for 안녕). This is the one hardcoded layout (`Ductus/Keyboard/Dubeolsik.swift`): macOS Korean input methods publish no `uchr` data, and 2-Set is a national standard (KS X 5002) by physical key position.
- **Persistence:** SwiftData, in the app layer only (`Ductus/Progress`). Progress is saved per keyboard layout. The engine stays free of SwiftData: its state is plain `Codable` (`StatsTracker` is stored as a JSON blob), and history math (`HistoryMath`) works on plain `DrillRecord` values so it is unit-tested. Raw keystrokes are never stored.

## Architecture

### 1. Adaptive engine (core, no UI imports)
The engine is what actually makes the user faster. It is statistical, not a neural network.
- Log every keystroke with a timestamp: expected char, typed char, physical keycode, latency since the previous key.
- Keep rolling stats per key and per bigram (e.g. `th`, `ue`): speed (ms) and accuracy.
- Generate drill text weighted toward the weakest keys and bigrams, using ONLY real words (and later real sentences) from the bundled library built from public-domain books (see CORPUS.md). Never generated pseudo-words or random letter strings. If the starting keys spell too few words, unlock more letters by frequency instead.
- Progressive unlocking: start with a few keys (home row for the active layout), add new keys as current ones reach target speed and accuracy.
- Updates after every keystroke.
- Reference: keybr.com uses a similar approach. keybr is AGPL-3.0, so learn from the idea but do NOT copy its code into this MIT project.

### 2. Local LLM: tested and parked (November 2026)
- The idea was a small local model writing drill sentences around weak keys and short coaching notes. We tested Qwen3 1.7B, Qwen3.5 2B (MLX, 4-bit) and Apple's built-in model (Foundation Models) on the same prompts and checks.
- Why it is parked:
  - No model can keep to the unlocked letters, so it never helps beginners.
  - Free sentences pass the word check but read as generic "AI slop" next to the bundled human-written sentences (up to 20,000 per language).
  - Coaching notes either invented facts (Qwen) or said nothing specific (Apple).
  - The cost is a 1 to 2 GB download or a macOS/Apple Intelligence requirement, an extra framework and network access.
- Written encouraging notes (our own phrasings filled with real facts) were also drafted and rejected: they did not feel right. Ductus shows plain stats, not coaching messages. Do not propose an LLM or coaching notes again unless asked; if a much better small model appears, the test harness approach (same prompts, Ductus word checks, side-by-side report) is the way to re-evaluate.

### 3. Keyboard HUD overlay
- Can be docked in the practice window or popped out. Popped out: borderless, non-activating floating `NSPanel` (never activates the app), adjustable opacity, draggable by its background. Clicking it makes it the typing target (key window) so practice works with the main window hidden. Optional click-through mode, where it never takes focus.
- Render the ACTIVE layout dynamically: read the current input source with `TISCopyCurrentKeyboardLayoutInputSource` and map physical keycodes to characters with `UCKeyTranslate`. No hardcoded layouts (the one exception is Korean 2-Set, see Languages). Redraw when the input source changes. For "Dvorak - QWERTY ⌘", show QWERTY labels while Command is held.
- Position keys by physical keycode. ANSI, ISO and JIS are drawn (`KeyboardGeometry`), detected with `KBGetLayoutType(LMGetKbdType())` with a Settings override.
- Command shortcut glow: while Command is held, softly tint (yellow-ish) the keys that act as common shortcuts (default Z X C V; configurable in Settings). Find them by translating with the Command modifier and locating the keycode that produces `z`, `x`, `c`, `v`. Never hardcode positions, so it works for any layout with Command remapping.
- Highlight keys on press. Inside the app this uses normal key events.
- Optional heatmap mode: tint each key by weakness using engine data.

### 4. System-wide highlighting (opt-in, implemented in `Ductus/Keyboard/GlobalKeyMonitor.swift`)
- Highlighting keys while typing in OTHER apps needs a global listener (`CGEventTap` or `NSEvent` global monitor) and the Input Monitoring permission.
- This is keylogger territory, so: opt-in only, clearly explained in the UI, keep events in memory only, never write raw keystrokes to disk outside practice sessions. macOS secure input (password fields) blocks taps, which is correct behavior.

## Interface languages

- UI text lives in `Ductus/Localizable.xcstrings` (String Catalog), translated into fr, es, de, it, pt-BR, nl, ja, zh-Hans and ko. The translations were made with AI; Settings says so next to the App language picker. Any new UI string needs all nine translations (same placeholders, no em-dashes, Apple's macOS terminology for that language). Run `python3 scripts/check_translations.py` after changing UI text; the release workflow runs it too and fails on any missing translation.
- Display helpers take `LocalizedStringKey`; text built in models uses `String(localized:)`. Names (Ductus, GitHub, Tatoeba, ...), key labels and units stay as they are.
- The App language switches live: `LanguageState` holds the choice, every window is wrapped in `LocalizedRoot` (sets `\.locale` and rebuilds on change), and text made in code uses `String(localized: ..., bundle: .ui)`. The choice is also written to `AppleLanguages` so the menu bar (built by macOS at launch) follows on the next launch. The catalog includes an `en` localization so switching back to English works live. Views that build text in code read `LanguageState.shared.locale` in their body so they redraw on a change (windows are not rebuilt, so open panels stay open). Debug-only test hooks: `DUCTUS_DEBUG_SWITCH_LANGUAGE=ko` switches 3 s after launch; `DUCTUS_DEBUG_SHOW_AUTHORS=1` opens the sentence author list with the About window.

## Project conventions

- **Colored log output** (terminal only, plain text in saved logs, disable with an env var such as `DUCTUS_NO_COLOR=1`):
  - red = errors / failures / crashes
  - bold red = crash report headers
  - cyan = stack frames
  - yellow = warnings, missing files, known/expected issues
  - green = success (done / ready / loaded / pass)
- **Debug mode** that can be toggled (env var like `DUCTUS_DEBUG=1` plus a hidden settings toggle): full logging, and keep running through errors where possible so one pass shows every problem. Implemented: hold Option while opening Settings to show the Debug section; debug mode also writes a plain-text log to the sandbox `Library/Logs/Ductus.log` (5 MB cap). Never log typed keys or pasted text.
- **Commits:** Author is Daggenthal (`112846802+Daggenthal@users.noreply.github.com`). Never use a real name anywhere public. Do NOT commit; leave changes uncommitted and suggest the commit command with `-S` (commits are SSH-signed). Add a `Co-Authored-By: Claude` trailer.
- **Writing (README, docs, UI text):** Direct and plain, no hype or AI-sounding flair. No em-dashes. Emojis are fine. Capitalize the first letter after a colon.
- **Long or complicated work:** Lay out the possible approaches, the reasoning and trade-offs for each, and why one was picked, before building. Give a progress update roughly every 10 minutes during long tasks.

## Dev environment

- M5 Pro MacBook Pro, 24GB unified memory, macOS 27 beta, Xcode beta.
- Minimum deployment target: to be decided (macOS 14+ is a reasonable default).

## Roadmap

1. App shell + keystroke capture + per-key / per-bigram stats (engine core, with unit tests).
2. Drill generator with progressive key unlocking.
3. Keyboard HUD overlay reading the active layout via TIS / UCKeyTranslate, with in-app highlighting.
4. Stats view (WPM, accuracy, per-key heatmap, history).
5. Opt-in system-wide highlighting.
6. ~~Optional local LLM drill generation and coaching.~~ Tested and parked, see Architecture section 2.
7. Website at the project domain with download (signed + notarized DMG, Sparkle updates later). Signing and notarizing wait until a paid Apple Developer account makes sense; the About window with credits and the app icon come first.
