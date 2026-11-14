A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.10.0

- **Back to typing:** The Study tab (HSK vocabulary and grammar) is gone. Ductus is a typing tutor first: learning a new layout or a new alphabet, and practicing it until it is muscle memory. Study pulled it toward being a language course, which apps like Anki and Pleco already do well. Your typing progress, races and texts are untouched.
- The tabs are Practice, Race, Text and History again (⌘1 to ⌘4).
- **A shorter layout menu:** Settings › Keyboard in Ductus now lists only your Mac's layouts, Dvorak and Colemak, and the layouts for your practice language. Browse All Layouts shows every other layout grouped by language, with search.

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
