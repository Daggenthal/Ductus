import AVFoundation
import DuctusLog

/// Soft key clicks and a mistake sound, synthesized at startup (no audio files).
/// The audio engine only runs while a sound is enabled.
@MainActor
final class KeySounds {
    private let engine = AVAudioEngine()
    /// Several players so fast typing does not cut sounds off.
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var click = makeClick()
    private lazy var mistake = makeMistake()

    var clicksOn = false
    var mistakesOn = false
    var volume: Float = 0.5 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// Starts or stops the audio engine to match the settings.
    func configure(clicks: Bool, mistakes: Bool, volume: Float) {
        clicksOn = clicks
        mistakesOn = mistakes
        self.volume = volume
        if clicks || mistakes { start() } else { stop() }
    }

    func keystroke(correct: Bool) {
        if !correct, mistakesOn { play(mistake) } else if clicksOn { play(click) }
    }

    private func start() {
        guard !engine.isRunning else { return }
        if players.isEmpty {
            for _ in 0..<6 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
        }
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            Log.error("Could not start key sounds: \(error)")
        }
    }

    private func stop() {
        guard engine.isRunning else { return }
        players.forEach { $0.stop() }
        engine.stop()
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard engine.isRunning, !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: - Synthesis

    private func buffer(seconds: Double, _ sample: (Double) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = sample(Double(i) / format.sampleRate) }
        return buffer
    }

    /// Short, soft tick: a burst of filtered noise with a fast decay.
    private func makeClick() -> AVAudioPCMBuffer {
        var last: Float = 0
        return buffer(seconds: 0.03) { t in
            let noise = Float.random(in: -1...1)
            last = last * 0.55 + noise * 0.45  // simple low-pass, takes the hiss off
            return last * Float(exp(-t * 180)) * 0.5
        }
    }

    /// Low, short "bump" for a mistake.
    private func makeMistake() -> AVAudioPCMBuffer {
        buffer(seconds: 0.12) { t in
            Float(sin(2 * .pi * 180 * t) * exp(-t * 28)) * 0.45
        }
    }
}
