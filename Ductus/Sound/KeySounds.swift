import AVFoundation
import DuctusLog

/// Soft key clicks and a mistake sound, synthesized at startup (no audio files).
/// The audio engine only runs while a sound is enabled.
@MainActor
final class KeySounds {
    private let engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?
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
    /// Plays a preview when a sound is turned on or the volume moves.
    func configure(clicks: Bool, mistakes: Bool, volume: Float) {
        let turnedOnClicks = clicks && !clicksOn
        let turnedOnMistakes = mistakes && !mistakesOn
        let volumeMoved = volume != self.volume
        clicksOn = clicks
        mistakesOn = mistakes
        self.volume = volume
        if clicks || mistakes { start() } else { stop() }
        guard configured else { configured = true; return }  // silent at launch
        if turnedOnMistakes {
            play(mistake)
        } else if turnedOnClicks || volumeMoved {
            previewThrottled()
        }
    }

    private var configured = false
    private var lastPreview = Date.distantPast

    /// The volume slider fires many times while dragging, so space previews out.
    private func previewThrottled() {
        guard Date().timeIntervalSince(lastPreview) > 0.15 else { return }
        lastPreview = Date()
        play(clicksOn ? click : mistake)
    }

    func keystroke(correct: Bool) {
        if !correct, mistakesOn { play(mistake) } else if clicksOn { play(click) }
    }

    private func start() {
        guard !engine.isRunning else { return }
        if configObserver == nil {
            // A new output device (headphones, display audio) stops the engine.
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            }
        }
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

    private func restart() {
        guard clicksOn || mistakesOn else { return }
        Log.info("Audio output changed, restarting key sounds")
        players.forEach { $0.stop() }
        engine.stop()
        start()
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

    /// Short tick: a noise transient plus a quick high "tock", pitched where
    /// laptop speakers play it clearly.
    private func makeClick() -> AVAudioPCMBuffer {
        var last: Float = 0
        return buffer(seconds: 0.04) { t in
            let noise = Float.random(in: -1...1)
            last = last * 0.3 + noise * 0.7
            let transient = last * Float(exp(-t * 400))
            let body = sin(2 * .pi * 1_900 * t) * 0.6 + sin(2 * .pi * 3_100 * t) * 0.3
            return (transient * 0.5 + Float(body * exp(-t * 140)) * 0.6)
        }
    }

    /// Short low "bonk" for a mistake. Two tones so small speakers still play it.
    private func makeMistake() -> AVAudioPCMBuffer {
        buffer(seconds: 0.16) { t in
            let tone = sin(2 * .pi * 330 * t) * 0.6 + sin(2 * .pi * 660 * t) * 0.35
            let attack = min(1, t / 0.004)  // no pop at the start
            return Float(tone * exp(-t * 18) * attack) * 0.8
        }
    }
}
