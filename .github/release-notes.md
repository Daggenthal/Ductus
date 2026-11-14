A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.6.1

- **Practice any language without switching your Mac's layout:** Pick a practice language your layout can't type (Hindi on U.S., say) and Ductus uses a matching layout inside its own windows, like Devanagari QWERTY for Hindi or Arabic PC for Arabic. Your Mac keeps its own layout in every other app, and nothing needs to be installed.
- **Keyboard in Ductus:** A new setting to type and see any macOS layout inside Ductus, such as Dvorak or Colemak, without enabling it in System Settings.

**Updating:** From 0.3.0 or later, use Ductus › Check for Updates… and click Download and Install. From 0.1.0, download this version by hand once (below). Keep Ductus in your Applications folder for updates to work.

## Download

- **Ductus-x.y.z.dmg:** Open it and drag Ductus into Applications.
- **Ductus-x.y.z.zip:** Unzip it and move Ductus into Applications.

## First launch

Ductus is not notarized by Apple yet (that needs a paid developer account), so macOS blocks it the first time:

1. Open Ductus. macOS says it cannot verify the developer. Click **Done**.
2. Open **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Ductus.
3. Confirm with **Open**. From then on Ductus opens normally.

If you use "Light up the floating keyboard in other apps", macOS asks for the Input Monitoring permission again after each update, until Ductus is notarized.

The source code is all here, and `SHA256SUMS.txt` lets you check the download (`shasum -a 256 -c SHA256SUMS.txt`).
