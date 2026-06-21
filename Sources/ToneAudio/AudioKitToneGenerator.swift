import Foundation

#if os(iOS)
import AVFoundation
import AudioKit
import os
import SoundpipeAudioKit
import ToneCore

/// `ToneGenerator` の本番実装。AudioKit のサインオシレータで純音を出力し、
/// `AVAudioSession` のライフサイクル / 割り込み / route 変更 / media reset を扱う。
///
/// ユーザ操作以外の停止では `onStopped` を呼ぶが、自動復帰はしない。
@MainActor
public final class AudioKitToneGenerator: ToneGenerator {
    public var onStopped: (@MainActor (ToneGeneratorStopReason) -> Void)?

    private static let logger = Logger(subsystem: "com.yutabee.tone", category: "ToneAudio")

    private let targetAmplitude: Float = 0.2
    private let envelopeDuration: Float = 0.008
    private let frequencyRampDuration: Float = 0.008
    private var engine: AudioEngine?
    private var oscillator: Oscillator?
    private var notificationObservers: [NSObjectProtocol] = []
    private var isRunning = false
    private var notificationGeneration = 0

    public init() {}

    // MainActor 隔離の stored property に触れるため isolated deinit を使う(Swift 6.1+)。
    isolated deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// `AVAudioSession`(`.playback`)を有効化し、サイン波オシレータを起動する。
    /// 再生中は graph を作り直さず、frequency ramp で更新する。
    public func play(frequency: Double) throws {
        guard frequency.isFinite, frequency > 0, Float(frequency).isFinite else {
            throw ToneGeneratorError.invalidFrequency
        }

        if isRunning, let oscillator {
            oscillator.$frequency.ramp(to: Float(frequency), duration: frequencyRampDuration)
            oscillator.$amplitude.ramp(to: targetAmplitude, duration: envelopeDuration)
            ensureNotificationObservers()
            return
        }

        do {
            try startAudioGraph(frequency: frequency)
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

    private func startAudioGraph(frequency: Double) throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw ToneGeneratorError.engineUnavailable
        }

        let engine = AudioEngine()
        let oscillator = Oscillator(frequency: Float(frequency), amplitude: 0)
        engine.output = oscillator

        self.engine = engine
        self.oscillator = oscillator

        oscillator.start()

        do {
            try engine.start()
            isRunning = true
            notificationGeneration += 1
            oscillator.$amplitude.ramp(to: targetAmplitude, duration: envelopeDuration)
        } catch {
            throw ToneGeneratorError.engineUnavailable
        }
    }

    private func stopAudioGraph(deactivateSession: Bool, useEnvelope: Bool) {
        notificationGeneration += 1
        let teardownGeneration = notificationGeneration
        isRunning = false

        let oscillator = self.oscillator
        let engine = self.engine
        self.oscillator = nil
        self.engine = nil

        guard useEnvelope, let oscillator else {
            oscillator?.stop()
            engine?.stop()
            if deactivateSession {
                deactivateSessionIfCurrent(teardownGeneration)
            }
            return
        }

        // クリック音回避のため amplitude を fade させ、完了後に非同期で graph を停止する
        // (main actor をブロックしない)。fade 中に再生が再開されたら世代不一致で session は止めない。
        oscillator.$amplitude.ramp(to: 0, duration: envelopeDuration)
        let fadeSeconds = Double(envelopeDuration)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fadeSeconds))
            oscillator.stop()
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
}
#endif
