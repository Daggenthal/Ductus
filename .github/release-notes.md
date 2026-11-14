A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.8.0

- **Grammar in Study:** Every grammar point of the revised HSK 3.0 syllabus, from HSK 1 to 7-9, with its English name and a link to look it up. HSK 1 and HSK 2 points come with example sentences to read with or without pinyin and to type, with the grammar highlighted. They are written by people (from Tatoeba), checked by hand and by a second review. Where no human sentence fit an HSK 2 point, a short sentence was written by AI, checked the same way, and labeled AI-written. Higher levels follow as they are checked.
- **Choose the characters, like a Chinese input method:** After typing a word's pinyin, pick its characters from a numbered list (1 to 9, or space). The list is shuffled, so you have to recognize them. You can turn this off in Settings.
- **Recall really is from memory:** On review cards the pinyin to type stays hidden, and the keyboard gives no hints, until you type it or press Return.
- **Return for the next card:** An answered card stays up with its grade until you press Return.
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
