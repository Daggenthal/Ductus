A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.2.0

- **Updates from inside the app:** Ductus › Check for Updates… shows what is new, and Download and Install updates Ductus for you. Nothing is downloaded or installed until you click. Turn on automatic checks in Settings if you like (off by default).
- **Ductus in your language:** The app itself is now in English, French, Spanish, German, Italian, Portuguese, Dutch, Japanese, Chinese and Korean. It follows your macOS language, or pick one in Settings › General, and it switches right away. These translations were made with AI, so some wording may not be completely accurate. Corrections are welcome.
- **Color keys by finger:** An optional on-screen keyboard mode that tints each key by the finger that presses it (Settings › Keyboard).
- **Fixes:** Collapsible sentence authors in About, and more of the app translated.

**Updating from 0.1.0:** Version 0.1.0 cannot update itself, so download this one by hand once (below). From 0.2.0 on, updates come through the app. Keep Ductus in your Applications folder for updates to work.

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
