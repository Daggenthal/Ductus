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
- **Everything runs locally.** No accounts, no telemetry, no network required for training.

## Architecture

### 1. Adaptive engine (core, no UI imports)
The engine is what actually makes the user faster. It is statistical, not a neural network.
- Log every keystroke with a timestamp: expected char, typed char, physical keycode, latency since the previous key.
- Keep rolling stats per key and per bigram (e.g. `th`, `ue`): speed (ms) and accuracy.
- Generate drill text weighted toward the weakest keys and bigrams, using ONLY real words (and later real sentences) from the bundled library built from public-domain books (see CORPUS.md). Never generated pseudo-words or random letter strings. If the starting keys spell too few words, unlock more letters by frequency instead.
- Progressive unlocking: start with a few keys (home row for the active layout), add new keys as current ones reach target speed and accuracy.
- Updates after every keystroke.
- Reference: keybr.com uses a similar approach. keybr is AGPL-3.0, so learn from the idea but do NOT copy its code into this MIT project.

### 2. Optional local LLM (toggle, off by default)
- The engine decides what to practice ("weak on `ue`, `gh`, right pinky"). A small local model (1 to 3B via MLX or llama.cpp) turns that into natural sentences full of those patterns, plus a short coaching note after each session.
- Generate the next drill in the background while the user types the current one, so the 1 to 2 second latency is hidden.
- Must be fully optional. The app must work perfectly without it.

### 3. Keyboard HUD overlay
- Can be docked in the practice window or popped out. Popped out: borderless, non-activating floating `NSPanel` (never activates the app), adjustable opacity, draggable by its background. Clicking it makes it the typing target (key window) so practice works with the main window hidden. Optional click-through mode, where it never takes focus.
- Render the ACTIVE layout dynamically: read the current input source with `TISCopyCurrentKeyboardLayoutInputSource` and map physical keycodes to characters with `UCKeyTranslate`. No hardcoded layouts. Redraw when the input source changes. For "Dvorak - QWERTY ⌘", show QWERTY labels while Command is held.
- Position keys by physical keycode (ANSI first; ISO/JIS later).
- Command shortcut glow: while Command is held, softly tint (yellow-ish) the keys that act as common shortcuts (default Z X C V; configurable set). Find them by translating with the Command modifier and locating the keycode that produces `z`, `x`, `c`, `v`. Never hardcode positions, so it works for any layout with Command remapping.
- Highlight keys on press. Inside the app this uses normal key events.
- Optional heatmap mode: tint each key by weakness using engine data.

### 4. System-wide highlighting (opt-in)
- Highlighting keys while typing in OTHER apps needs a global listener (`CGEventTap` or `NSEvent` global monitor) and the Input Monitoring permission.
- This is keylogger territory, so: opt-in only, clearly explained in the UI, keep events in memory only, never write raw keystrokes to disk outside practice sessions. macOS secure input (password fields) blocks taps, which is correct behavior.

## Project conventions

- **Colored log output** (terminal only, plain text in saved logs, disable with an env var such as `DUCTUS_NO_COLOR=1`):
  - red = errors / failures / crashes
  - bold red = crash report headers
  - cyan = stack frames
  - yellow = warnings, missing files, known/expected issues
  - green = success (done / ready / loaded / pass)
- **Debug mode** that can be toggled (env var like `DUCTUS_DEBUG=1` plus a hidden settings toggle): full logging, and keep running through errors where possible so one pass shows every problem.
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
6. Optional local LLM drill generation and coaching.
7. Website at the project domain with download (signed + notarized DMG, Sparkle updates later).
