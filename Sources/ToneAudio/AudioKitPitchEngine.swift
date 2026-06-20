import Foundation

/// `ToneAudio` モジュールのプラットフォーム可用性マーカー。
/// macOS では実機オーディオエンジンを提供しない(`swift test` は ToneCore のみで完結する)。
public enum ToneAudioModule {
    /// 実機 `AudioKitPitchEngine` が利用可能なプラットフォームか。
    public static let isPitchEngineAvailable: Bool = {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }()
}

#if os(iOS)
import AVFoundation
import AudioKit
import SoundpipeAudioKit
import ToneCore

/// `PitchEngine` の本番実装。AudioKit の `PitchTap`(`SoundpipeAudioKit`)で単音ピッチを検出し、
/// `AVAudioSession` のライフサイクル / 割り込み / route 変更 / media reset を扱う。
///
/// オーディオスレッドのコールバックは必ず main actor へ marshaling してから `onReading` を呼ぶ。
@MainActor
public final class AudioKitPitchEngine: PitchEngine {
    public var onReading: (@MainActor (PitchReading) -> Void)?

    /// `PitchReading.timestamp` を打つための monotonic 時刻源。ViewModel の無音判定と同じ基準に揃える。
    private let clock: any Clock
    private var engine: AudioEngine?
    private var tap: PitchTap?
    private var silentOutput: Mixer?
    private var notificationObservers: [NSObjectProtocol] = []
    private var wantsRunning = false
    private var isRunning = false
    private var isInterrupted = false
    private var readingGeneration = 0
    private var notificationGeneration = 0

    public init(clock: any Clock = MonotonicClock()) {
        self.clock = clock
    }

    // MainActor 隔離の stored property に触れるため isolated deinit を使う(Swift 6.1+)。
    isolated deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// iOS 17+ の `AVAudioApplication.requestRecordPermission` で権限を要求する。
    public func requestPermission() async -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            return granted ? .granted : .denied
        @unknown default:
            return .denied
        }
    }

    /// `granted` 前提で `AVAudioSession`(`.record` / `.measurement`)を有効化し、
    /// `AudioEngine` + `PitchTap`(bufferSize 4096)を起動する。冪等。
    public func start() throws {
        wantsRunning = true
        guard !isRunning else {
            ensureNotificationObservers()
            return
        }

        do {
            try startAudioGraph()
            isInterrupted = false
            ensureNotificationObservers()
        } catch {
            wantsRunning = false
            stopAudioGraph(deactivateSession: true)
            removeNotificationObservers()
            throw error
        }
    }

    /// タップ停止 + セッション無効化。冪等。stop 後は onReading を呼ばない。
    public func stop() {
        wantsRunning = false
        isInterrupted = false
        stopAudioGraph(deactivateSession: true)
        removeNotificationObservers()
    }

    private func startAudioGraph() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        } catch {
            throw PitchEngineError.engineUnavailable
        }

        guard session.isInputAvailable else {
            throw PitchEngineError.inputUnavailable
        }

        do {
            try session.setActive(true)
        } catch {
            if !session.isInputAvailable {
                throw PitchEngineError.inputUnavailable
            }
            throw PitchEngineError.engineUnavailable
        }

        guard session.isInputAvailable else {
            try? session.setActive(false)
            throw PitchEngineError.inputUnavailable
        }

        let engine = AudioEngine()
        guard let input = engine.input else {
            try? session.setActive(false)
            throw PitchEngineError.inputUnavailable
        }

        let silentOutput = Mixer(input, name: "ToneAudio Silent Output")
        silentOutput.volume = 0
        engine.output = silentOutput

        readingGeneration += 1
        let generation = readingGeneration
        let tap = PitchTap(input, bufferSize: 4096) { [weak self] frequencies, amplitudes in
            guard let frequency = frequencies.first, let amplitude = amplitudes.first else { return }

            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.readingGeneration == generation else { return }

                let reading = PitchReading(
                    frequency: Double(frequency),
                    amplitude: Double(amplitude),
                    timestamp: self.clock.now
                )
                self.onReading?(reading)
            }
        }

        self.engine = engine
        self.silentOutput = silentOutput
        self.tap = tap

        tap.start()

        do {
            try engine.start()
            isRunning = true
            notificationGeneration += 1
        } catch {
            stopAudioGraph(deactivateSession: true)
            throw PitchEngineError.engineUnavailable
        }
    }

    private func stopAudioGraph(deactivateSession: Bool) {
        readingGeneration += 1
        notificationGeneration += 1
        isRunning = false
        tap?.stop()
        tap = nil
        engine?.stop()
        engine = nil
        silentOutput = nil

        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
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
                let optionRawValue = Self.uintValue(
                    in: notification.userInfo,
                    forKey: AVAudioSessionInterruptionOptionKey
                )

                Task { @MainActor [weak self] in
                    guard let self, self.notificationGeneration == observerGeneration else { return }
                    self.handleInterruption(typeRawValue: typeRawValue, optionRawValue: optionRawValue)
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

    private func resetNotificationObserversForCurrentGeneration() {
        removeNotificationObservers()
        ensureNotificationObservers()
    }

    private func handleInterruption(typeRawValue: UInt?, optionRawValue: UInt?) {
        guard let typeRawValue,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeRawValue)
        else { return }

        switch interruptionType {
        case .began:
            isInterrupted = true
            stopAudioGraph(deactivateSession: false)
            resetNotificationObserversForCurrentGeneration()
        case .ended:
            isInterrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue: optionRawValue ?? 0)
            if options.contains(.shouldResume) {
                restartAudioGraphAfterSystemChange()
            } else {
                wantsRunning = false
            }
        @unknown default:
            isInterrupted = true
            stopAudioGraph(deactivateSession: false)
            resetNotificationObserversForCurrentGeneration()
        }
    }

    private func handleRouteChange(reasonRawValue: UInt?) {
        if let reasonRawValue,
           AVAudioSession.RouteChangeReason(rawValue: reasonRawValue) == .categoryChange
        {
            return
        }

        restartAudioGraphAfterSystemChange()
    }

    private func handleMediaServicesReset() {
        restartAudioGraphAfterSystemChange()
    }

    private func restartAudioGraphAfterSystemChange() {
        guard wantsRunning, !isInterrupted else { return }

        stopAudioGraph(deactivateSession: false)
        try? startAudioGraph()
        resetNotificationObserversForCurrentGeneration()
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
