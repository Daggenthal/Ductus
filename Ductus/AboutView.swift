import AppKit
import DuctusEngine
import SwiftUI

/// About Ductus: what it is, the license, and credits for every source of text
/// and every tool used to build the word lists.
struct AboutView: View {
    @State private var showingAuthors = false

    private static let sourceURL = URL(string: "https://github.com/Daggenthal/Ductus")!
    private static let licenseURL = URL(string: "https://github.com/Daggenthal/Ductus/blob/main/LICENSE")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.bottom, 18)
            Divider()
            ScrollView {
                credits
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("© 2026 Daggenthal. Free and open source under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .frame(width: 480, height: 600)
        .sheet(isPresented: $showingAuthors) { SentenceAuthorsSheet() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Ductus").font(.title.weight(.semibold))
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("A typing tutor for learning a new keyboard layout.")
                .padding(.top, 4)
            Text("In calligraphy, the ductus is the order, direction and rhythm of the strokes that make a letter. That is muscle memory, which is what Ductus trains.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack(spacing: 16) {
                Link("Source Code", destination: Self.sourceURL)
                Link("MIT License", destination: Self.licenseURL)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Credits").font(.headline)
            credit(
                "Words and sentences",
                "From public-domain books on Project Gutenberg, in English, French, Spanish, German, Italian, Portuguese and Dutch.",
                link: ("gutenberg.org", "https://www.gutenberg.org")
            )
            VStack(alignment: .leading, spacing: 6) {
                credit(
                    "Japanese, Chinese and Korean sentences",
                    "By the contributors of Tatoeba, used under CC BY 2.0 FR. Changed for typing: romanized and split into chunks for Japanese and Chinese (Chinese converted to Simplified), and paired with the 2-Set keys for Korean.",
                    link: ("tatoeba.org", "https://tatoeba.org")
                )
                Button("Sentence Authors…") { showingAuthors = true }
            }
            credit(
                "Tools used to build the word lists",
                "fugashi and unidic-lite (MIT, UniDic under BSD) for Japanese readings, jieba (MIT) for Chinese words, pypinyin (MIT) for pinyin, and OpenCC (Apache 2.0) for Simplified Chinese. None of them ship with the app. The full list of books and tools is in CORPUS.md in the source code."
            )
            credit(
                "Pasted text",
                "Japanese and Chinese you paste into the Text tab are read with the text tools built into macOS."
            )
            credit(
                "Thanks",
                "The adaptive approach was inspired by keybr.com. No code from it is used."
            )
        }
    }

    private func credit(_ title: LocalizedStringKey, _ text: LocalizedStringKey, link: (String, String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let link, let url = URL(string: link.1) {
                Link(link.0, destination: url).font(.callout)
            }
        }
    }
}

/// Opens the About window from the app menu.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Ductus") { openWindow(id: AboutView.windowID) }
        }
    }
}

extension AboutView {
    static let windowID = "about"
}
