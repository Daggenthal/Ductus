A free, open source typing tutor for macOS, for learning a new keyboard layout. Works on Apple Silicon and Intel Macs with macOS 14 or newer.

## What's new in 0.9.0

- **Grammar for every HSK level:** HSK 3, 4, 5, 6 and 7-9 now have example sentences for every grammar point, with the grammar highlighted. Human-written sentences from Tatoeba where one fit, short AI-written ones (labeled) where none did, all checked by hand and by a second review.
- **Read aloud:** Listen to words and grammar sentences in Mandarin, with each word highlighted as it is spoken. It uses your Mac's own voices, on your Mac. Pick the voice and speed in Settings › Study, and download nicer Enhanced or Premium voices in System Settings. Recall cards only read the word once you have answered, so it doesn't give the answer away.
- **More accurate pinyin:** Readings of characters with several pronunciations (得, 着, 长, 为, 倒, 重, 地 and more) are now chosen from the sentence around them.

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
