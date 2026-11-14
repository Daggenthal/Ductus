A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.8.0

- **Grammar in Study:** Every grammar point of the revised HSK 3.0 syllabus, from HSK 1 to 7-9, with its English name and a link to look it up. HSK 1 points come with example sentences written by people (from Tatoeba) and their English translations, each checked by hand, to read with or without pinyin and to type. Examples for higher levels follow as they are checked.
- **I Know This Word:** Skip a word you already know. It comes back for review in about six months.
- **Study in History:** Answers per day, reviews due this week, and your recently studied words. Study Again puts a word back as new, for example if you pressed I Know This Word by mistake.
- **Study types pinyin on your Mac's layout:** If your practice layout cannot type Latin letters (Russian, Hindi, Arabic...), the Study tab uses your Mac's own layout and switches back when you leave.

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
