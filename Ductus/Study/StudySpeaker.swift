import AVFoundation
import Foundation
import Observation

/// Reads Study's Chinese aloud with the Mac's own voices, all on this Mac, and
/// reports which word is being spoken so the view can highlight it (你好 lights
/// up as one word, then 吗).
@MainActor
@Observable
final class StudySpeaker: NSObject {
    /// The text being read, and the range of it being spoken right now.
    private(set) var speakingText: String?
    private(set) var spokenRange: Range<Int>?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Mandarin voices installed on this Mac (more can be downloaded in System
    /// Settings › Accessibility › Spoken Content › System Voice › Manage Voices).
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh-CN") || $0.language.hasPrefix("zh-TW") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    func speak(_ text: String) {
        if speakingText == text, synthesizer.isSpeaking {
            stop()
            return
        }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        let defaults = UserDefaults.standard
        let chosen = defaults.string(forKey: SettingsKey.studyVoice) ?? ""
        utterance.voice = AVSpeechSynthesisVoice(identifier: chosen)
            ?? Self.voices.first
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        // 0.5 is a slow, clear pace for learning; 1 is the voice's normal speed.
        let speed = defaults.object(forKey: SettingsKey.studySpeechSpeed) == nil ? 0.8 : defaults.double(forKey: SettingsKey.studySpeechSpeed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(min(1.2, max(0.4, speed)))
        speakingText = text
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingText = nil
        spokenRange = nil
    }

    func isSpeaking(_ text: String) -> Bool { speakingText == text }
}

extension StudySpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        guard let range = Range(characterRange, in: text) else { return }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        Task { @MainActor [weak self] in self?.spokenRange = start..<end }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.speakingText = nil
            self?.spokenRange = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.spokenRange = nil }
    }
}
