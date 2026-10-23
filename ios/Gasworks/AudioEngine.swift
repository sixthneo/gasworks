import AVFoundation

/// Wires the synth kernel into AVAudioEngine:
/// synth (voices + sequencer + drive) → delay → reverb → speaker.
///
/// All audio-session and engine work happens on a private serial queue, because those calls can
/// block for seconds while the system audio server wakes up. The UI never waits on them: pad hits
/// made before the engine is running are queued in the kernel and play as soon as it starts.
final class AudioEngine {
    /// The kernel always runs at 48 kHz; AVAudioEngine converts to whatever the hardware uses.
    static let sampleRate: Double = 48_000

    let core = SynthCore(sampleRate: AudioEngine.sampleRate)

    private let queue = DispatchQueue(label: "gasworks.audio", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private var configured = false

    init() {
        let kernel = core.kernel
        queue.async { [weak self] in self?.configure(kernel: kernel) }
    }

    // MARK: Public (main thread)

    /// Safe to call often: does nothing if the engine is already running.
    func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    /// reverb, delay mix, delay time and repeats are all 0…1 knob values.
    func setEffects(reverb rev: Double, delay mix: Double, time: Double, repeats: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.reverb.wetDryMix = Float(rev * 70)
            self.delay.wetDryMix = Float(mix * 60)
            self.delay.delayTime = 0.05 + time * 0.85
            self.delay.feedback = Float(repeats * 82)
        }
    }

    // MARK: Audio queue

    private func configure(kernel: SynthKernel) {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps sound on with the silent switch; mixWithOthers lets you toot over your music.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else { return }
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            kernel.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }

        reverb.loadFactoryPreset(.largeHall)
        delay.lowPassCutoff = 2400

        engine.attach(source)
        engine.attach(delay)
        engine.attach(reverb)
        engine.connect(source, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRestart(_:)),
            name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRestart(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification, object: session)

        configured = true
        startOnQueue()
    }

    private func startOnQueue() {
        guard configured, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        do { try engine.start() } catch { print("Gasworks: audio engine failed to start: \(error)") }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended else { return }
        start()
    }

    @objc private func handleRestart(_ note: Notification) {
        start()
    }
}
