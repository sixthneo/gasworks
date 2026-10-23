import AVFoundation

/// Wires the synth kernel into AVAudioEngine:
/// synth (voices + sequencer + drive) → delay → reverb → speaker.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private var source: AVAudioSourceNode?
    let core: SynthCore

    init() {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps sound on with the silent switch; mixWithOthers lets you toot over your music.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)

        var sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000 }
        core = SynthCore(sampleRate: sampleRate)

        let kernel = core.kernel
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            kernel.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
        source = node

        reverb.loadFactoryPreset(.largeHall)
        delay.lowPassCutoff = 2400

        engine.attach(node)
        engine.attach(delay)
        engine.attach(reverb)
        engine.connect(node, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange, object: engine)

        start()
    }

    func start() {
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        do { try engine.start() } catch { print("Gasworks: audio engine failed to start: \(error)") }
    }

    /// reverb, delay mix, delay time and repeats are all 0…1 knob values.
    func setEffects(reverb rev: Double, delay mix: Double, time: Double, repeats: Double) {
        reverb.wetDryMix = Float(rev * 70)
        delay.wetDryMix = Float(mix * 60)
        delay.delayTime = 0.05 + time * 0.85
        delay.feedback = Float(repeats * 82)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended {
            DispatchQueue.main.async { self.start() }
        }
    }

    @objc private func handleConfigChange(_ note: Notification) {
        DispatchQueue.main.async { self.start() }
    }
}
