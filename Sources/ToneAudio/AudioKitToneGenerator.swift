import Foundation

#if os(iOS)
import AVFoundation
import AudioKit
import os
import SoundpipeAudioKit
import ToneCore

/// `ToneGenerator` の本番実装。AudioKit のオシレータでリファレンストーンを出力し、
/// `AVAudioSession` のライフサイクル / 割り込み / route 変更 / media reset を扱う。
///
/// ユーザ操作以外の停止では `onStopped` を呼ぶが、自動復帰はしない。
@MainActor
public final class AudioKitToneGenerator: ToneGenerator {
    public var onStopped: (@MainActor (ToneGeneratorStopReason) -> Void)?

    private static let logger = Logger(subsystem: "com.yutabee.tone", category: "ToneAudio")

    private let envelopeDuration: Float = 0.008
    private let frequencyRampDuration: Float = 0.008
    private var engine: AudioEngine?
    private var mixer: Mixer?
    private var voice: ToneVoice?
    private var currentTimbre: ToneTimbre?
    private var notificationObservers: [NSObjectProtocol] = []
    private var isRunning = false
    private var notificationGeneration = 0

    public init() {}

    // MainActor 隔離の stored property に触れるため isolated deinit を使う(Swift 6.1+)。
    isolated deinit {
        voice?.stop()
        engine?.stop()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// `AVAudioSession`(`.playback`)を有効化し、選択音色の voice を起動する。
    /// 同一音色で再生中は graph を作り直さず、frequency / amplitude ramp で更新する。
    public func play(frequency: Double, timbre: ToneTimbre) throws {
        guard frequency.isFinite, frequency > 0, Float(frequency).isFinite else {
            throw ToneGeneratorError.invalidFrequency
        }

        if isRunning, let voice, timbre == currentTimbre {
            voice.rampFrequency(to: frequency, duration: frequencyRampDuration)
            voice.rampAmplitude(to: Self.targetAmplitude(for: timbre), duration: envelopeDuration)
            ensureNotificationObservers()
            return
        }

        if isRunning {
            crossfadeToVoice(frequency: frequency, timbre: timbre)
            ensureNotificationObservers()
            return
        }

        do {
            try startAudioGraph(frequency: frequency, timbre: timbre)
            ensureNotificationObservers()
        } catch {
            stopAudioGraph(deactivateSession: true, useEnvelope: false)
            removeNotificationObservers()
            throw ToneGeneratorError.engineUnavailable
        }
    }

    /// ユーザ操作による停止。冪等。`onStopped` は呼ばない。
    public func stop() {
        stopAudioGraph(deactivateSession: true, useEnvelope: true)
        removeNotificationObservers()
    }

    private func startAudioGraph(frequency: Double, timbre: ToneTimbre) throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw ToneGeneratorError.engineUnavailable
        }

        let engine = AudioEngine()
        let mixer = Mixer()
        let voice = Self.makeVoice(frequency: frequency, timbre: timbre, amplitude: 0)
        mixer.addInput(voice.node)
        engine.output = mixer

        self.engine = engine
        self.mixer = mixer
        self.voice = voice
        currentTimbre = timbre

        voice.start()

        do {
            try engine.start()
            isRunning = true
            notificationGeneration += 1
            voice.rampAmplitude(to: Self.targetAmplitude(for: timbre), duration: envelopeDuration)
        } catch {
            throw ToneGeneratorError.engineUnavailable
        }
    }

    private func crossfadeToVoice(frequency: Double, timbre: ToneTimbre) {
        guard engine != nil, let mixer, let oldVoice = voice else {
            do {
                try startAudioGraph(frequency: frequency, timbre: timbre)
            } catch {
                stopAudioGraph(deactivateSession: true, useEnvelope: false)
                removeNotificationObservers()
            }
            return
        }

        let newVoice = Self.makeVoice(frequency: frequency, timbre: timbre, amplitude: 0)
        mixer.addInput(newVoice.node)
        newVoice.start()

        // 音色変更は完全停止ではないため session / observer は維持し、Mixer 内で voice を crossfade する。
        oldVoice.rampAmplitude(to: 0, duration: envelopeDuration)
        newVoice.rampAmplitude(to: Self.targetAmplitude(for: timbre), duration: envelopeDuration)

        voice = newVoice
        currentTimbre = timbre

        let fadeSeconds = Double(envelopeDuration) + 0.02
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fadeSeconds))
            mixer.removeInput(oldVoice.node)
            oldVoice.stop()
        }
    }

    private func stopAudioGraph(deactivateSession: Bool, useEnvelope: Bool) {
        notificationGeneration += 1
        let teardownGeneration = notificationGeneration
        isRunning = false

        let voice = self.voice
        let engine = self.engine
        self.voice = nil
        self.engine = nil
        self.mixer = nil
        currentTimbre = nil

        guard useEnvelope, let voice else {
            voice?.stop()
            engine?.stop()
            if deactivateSession {
                deactivateSessionIfCurrent(teardownGeneration)
            }
            return
        }

        // クリック音回避のため amplitude を fade させ、完了後に非同期で graph を停止する
        // (main actor をブロックしない)。fade 中に再生が再開されたら世代不一致で session は止めない。
        voice.rampAmplitude(to: 0, duration: envelopeDuration)
        let fadeSeconds = Double(envelopeDuration)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fadeSeconds))
            voice.stop()
            engine?.stop()
            if deactivateSession {
                self?.deactivateSessionIfCurrent(teardownGeneration)
            }
        }
    }

    /// fade teardown が依然として最新世代のときだけ session を無効化する
    /// (fade 中に play() が再開していたら新しい session を殺さない)。
    private func deactivateSessionIfCurrent(_ generation: Int) {
        guard notificationGeneration == generation else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            Self.logger.error("AVAudioSession の無効化に失敗: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureNotificationObservers() {
        guard notificationObservers.isEmpty else { return }

        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let observerGeneration = notificationGeneration

        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { notification in
                let typeRawValue = Self.uintValue(
                    in: notification.userInfo,
                    forKey: AVAudioSessionInterruptionTypeKey
                )

                Task { @MainActor [weak self] in
                    guard let self, self.notificationGeneration == observerGeneration else { return }
                    self.handleInterruption(typeRawValue: typeRawValue)
                }
            }
        )

        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { notification in
                let reasonRawValue = Self.uintValue(
                    in: notification.userInfo,
                    forKey: AVAudioSessionRouteChangeReasonKey
                )

                Task { @MainActor [weak self] in
                    guard let self, self.notificationGeneration == observerGeneration else { return }
                    self.handleRouteChange(reasonRawValue: reasonRawValue)
                }
            }
        )

        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in
                    guard let self, self.notificationGeneration == observerGeneration else { return }
                    self.handleMediaServicesReset()
                }
            }
        )
    }

    private func removeNotificationObservers() {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func handleInterruption(typeRawValue: UInt?) {
        guard let typeRawValue,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeRawValue)
        else { return }

        switch interruptionType {
        case .began:
            stopAfterSystemChange(reason: .interruption, deactivateSession: false)
        case .ended:
            break
        @unknown default:
            stopAfterSystemChange(reason: .interruption, deactivateSession: false)
        }
    }

    private func handleRouteChange(reasonRawValue: UInt?) {
        guard let reasonRawValue,
              AVAudioSession.RouteChangeReason(rawValue: reasonRawValue) == .oldDeviceUnavailable
        else { return }

        stopAfterSystemChange(reason: .routeChange, deactivateSession: true)
    }

    private func handleMediaServicesReset() {
        stopAfterSystemChange(reason: .mediaServicesReset, deactivateSession: false)
    }

    private func stopAfterSystemChange(reason: ToneGeneratorStopReason, deactivateSession: Bool) {
        guard isRunning else { return }

        stopAudioGraph(deactivateSession: deactivateSession, useEnvelope: true)
        removeNotificationObservers()
        onStopped?(reason)
    }

    private nonisolated static func uintValue(in userInfo: [AnyHashable: Any]?, forKey key: String) -> UInt? {
        guard let value = userInfo?[key] else { return nil }

        if let value = value as? UInt {
            return value
        }

        if let value = value as? Int, value >= 0 {
            return UInt(value)
        }

        return (value as? NSNumber)?.uintValue
    }

    private nonisolated static func targetAmplitude(for timbre: ToneTimbre) -> Float {
        switch timbre {
        case .sine:
            return 0.2
        case .triangle:
            return 0.18
        case .sawtooth:
            return 0.13
        case .fork:
            return 0.16
        }
    }

    private static func makeVoice(
        frequency: Double,
        timbre: ToneTimbre,
        amplitude: Float
    ) -> ToneVoice {
        let frequency = Float(frequency)
        switch timbre {
        case .sine:
            return .oscillator(Oscillator(waveform: Table(.sine), frequency: frequency, amplitude: amplitude))
        case .triangle:
            return .oscillator(Oscillator(waveform: Table(.triangle), frequency: frequency, amplitude: amplitude))
        case .sawtooth:
            return .oscillator(Oscillator(waveform: Table(.sawtooth), frequency: frequency, amplitude: amplitude))
        case .fork:
            return .fm(
                FMOscillator(
                    baseFrequency: frequency,
                    carrierMultiplier: 1.0,
                    modulatingMultiplier: 2.0,
                    modulationIndex: 1.5,
                    amplitude: amplitude
                )
            )
        }
    }

    private enum ToneVoice {
        case oscillator(Oscillator)
        case fm(FMOscillator)

        var node: any Node {
            switch self {
            case .oscillator(let oscillator):
                return oscillator
            case .fm(let oscillator):
                return oscillator
            }
        }

        func start() {
            node.start()
        }

        func stop() {
            node.stop()
        }

        func rampFrequency(to frequency: Double, duration: Float) {
            let frequency = Float(frequency)
            switch self {
            case .oscillator(let oscillator):
                oscillator.$frequency.ramp(to: frequency, duration: duration)
            case .fm(let oscillator):
                oscillator.$baseFrequency.ramp(to: frequency, duration: duration)
            }
        }

        func rampAmplitude(to amplitude: Float, duration: Float) {
            switch self {
            case .oscillator(let oscillator):
                oscillator.$amplitude.ramp(to: amplitude, duration: duration)
            case .fm(let oscillator):
                oscillator.$amplitude.ramp(to: amplitude, duration: duration)
            }
        }
    }
}
#endif
