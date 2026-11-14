A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.7.0

- **Study tab:** Learn Chinese vocabulary from the revised HSK 3.0 word lists (2025), HSK 1 to 7-9, with spaced repetition. Each card shows the characters, pinyin and meaning, and you type the pinyin. How you type it is the grade: a clean, quick answer pushes the word further out, a miss brings it back sooner. Choose how many new words a day, keep going whenever you like, and practice the words you already know.
- **Your choice of hints:** Show or hide the characters, pinyin and meaning when recalling. Press Return to see the answer if you are stuck.
- History moves to ⌘5; Study is ⌘4.

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
