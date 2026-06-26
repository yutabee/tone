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
import os
import SoundpipeAudioKit
import ToneCore

/// `PitchEngine` の本番実装。AudioKit の `PitchTap`(`SoundpipeAudioKit`)で単音ピッチを検出し、
/// `AVAudioSession` のライフサイクル / 割り込み / route 変更 / media reset を扱う。
///
/// オーディオスレッドのコールバックは必ず main actor へ marshaling してから `onReading` を呼ぶ。
@MainActor
public final class AudioKitPitchEngine: PitchEngine {
    public var onReading: (@MainActor (PitchReading) -> Void)?
    public var onStopped: (@MainActor (PitchEngineError) -> Void)?

    private static let logger = Logger(subsystem: "com.yutabee.tone", category: "PitchEngine")

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
    /// system-change 再起動チェーンの世代印。start / stop / 新たな再起動で増やし、
    /// in-flight な bounded-retry チェーンが手動の起動/停止を追い越して二重 start するのを防ぐ。
    private var restartGeneration = 0
    /// system-change 再起動の bounded retry 前 delay(HAL settle 待ち)。
    /// `Swift.Duration` を明示する(ToneAudio では AudioKit 由来の `Duration` が衝突するため)。
    private let restartRetryDelays: [Swift.Duration] = [.milliseconds(150), .milliseconds(400)]

    public init(clock: any Clock = MonotonicClock()) {
        self.clock = clock
    }

    // MainActor 隔離の stored property に触れるため isolated deinit を使う(Swift 6.1+)。
    isolated deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// ダイアログを伴わない現在のマイク権限(再起動前の取り消し検知用)。
    public var currentPermission: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .notDetermined
        @unknown default: return .denied
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

    /// `granted` 前提で `AVAudioSession`(`.playAndRecord` / `.measurement`)を有効化し、
    /// `AudioEngine` + `PitchTap`(bufferSize 4096)を起動する。冪等。
    public func start() throws {
        wantsRunning = true
        restartGeneration += 1 // in-flight な system-change 再起動チェーンを無効化する。
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
        restartGeneration += 1 // in-flight な system-change 再起動チェーンを無効化する。
        stopAudioGraph(deactivateSession: true)
        removeNotificationObservers()
    }

    private func startAudioGraph() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            // `.playAndRecord` を使う理由: 下で `engine.output`(無音 Mixer)を hardware output へ
            // 接続するため、出力 route を持つカテゴリが必要。`.record` は出力 route を持たず、
            // 出力ノードへ接続した graph の `engine.start()` が実機で失敗し得る
            // (= 初回付与直後の `.engineUnavailable` の主因。この変更が根本修正)。
            // mixWithOthers は付けない: チューナーはクリーンな入力が要るので他アプリ音源は止める
            //   (鳴っている音楽がマイクに混ざり誤検出するのを避ける)。退出時は下の
            //   `.notifyOthersOnDeactivation` で相手を復帰させる。
            // `.allowBluetoothHFP` は外した: 8/16kHz の BT HFP mic はピッチ検出を劣化させるため、
            //   広帯域の built-in / 有線入力を優先する(下の setPreferredInput と対)。
            try session.setCategory(.playAndRecord, mode: .measurement, options: [])
        } catch {
            logFailure(stage: "setCategory", error: error, session: session)
            throw PitchEngineError.engineUnavailable
        }

        guard session.isInputAvailable else {
            logFailure(stage: "preActivate.inputUnavailable", error: nil, session: session)
            throw PitchEngineError.inputUnavailable
        }

        do {
            try session.setActive(true)
        } catch {
            if !session.isInputAvailable {
                logFailure(stage: "setActive.inputUnavailable", error: error, session: session)
                throw PitchEngineError.inputUnavailable
            }
            logFailure(stage: "setActive", error: error, session: session)
            throw PitchEngineError.engineUnavailable
        }

        guard session.isInputAvailable else {
            logFailure(stage: "postActivate.inputUnavailable", error: nil, session: session)
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            throw PitchEngineError.inputUnavailable
        }

        // BT/AirPods 接続時でもチューニングは広帯域の built-in mic で行う(HFP narrowband 回避)。
        // 既に built-in が入力なら呼ばない: 自前の setPreferredInput が起動直後に route 変更通知を
        // 誘発し無駄な再起動を起こすのを避ける。best-effort: 失敗しても既定入力で続行する。
        if session.currentRoute.inputs.first?.portType != .builtInMic,
           let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtInMic)
        }

        let engine = AudioEngine()
        guard let input = engine.input else {
            logFailure(stage: "engine.input.nil", error: nil, session: session)
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
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
            logFailure(stage: "engine.start", error: error, session: session)
            stopAudioGraph(deactivateSession: true)
            throw PitchEngineError.engineUnavailable
        }
    }

    /// `startAudioGraph` の失敗を、潰す前の生の `NSError`(domain / code)と
    /// その瞬間の権限・入力状態つきで記録する。`.engineUnavailable` / `.inputUnavailable` の
    /// どちらに潰れたか、どの段で落ちたかを実機ログ(Console / sysdiagnose)から判別するため。
    private func logFailure(stage: String, error: Error?, session: AVAudioSession) {
        let permission: String
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permission = "granted"
        case .denied: permission = "denied"
        case .undetermined: permission = "undetermined"
        @unknown default: permission = "unknown"
        }

        let detail: String
        if let error {
            let nsError = error as NSError
            detail = "\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)"
        } else {
            detail = "-"
        }

        let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")

        Self.logger.error(
            "startAudioGraph failed: stage=\(stage, privacy: .public) permission=\(permission, privacy: .public) inputAvailable=\(session.isInputAvailable, privacy: .public) inputs=[\(inputs, privacy: .public)] error=\(detail, privacy: .public)"
        )
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
            // 退出時に他アプリの音楽 / podcast を復帰させる。
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
            // 前面のチューナーは音が無いと無意味なので、`.shouldResume` の有無に依らず復帰を試みる。
            // 復帰失敗は restartAudioGraphAfterSystemChange 内で `onStopped` 経由 UI に通知する
            // (旧実装は shouldResume 無しで無言停止 → フリーズした 'listening' に陥っていた)。
            restartAudioGraphAfterSystemChange()
        @unknown default:
            isInterrupted = true
            stopAudioGraph(deactivateSession: false)
            resetNotificationObserversForCurrentGeneration()
        }
    }

    private func handleRouteChange(reasonRawValue: UInt?) {
        guard let reasonRawValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRawValue)
        else { return }

        // 入力ルートに実際に影響する変化でだけ作り直す。`.playAndRecord` では出力都合の変化
        // (speaker/receiver 遷移・他アプリ再生・.routeConfigurationChange/.override)も
        // routeChange を出すため、それらで毎回 teardown/rebuild しないよう絞り込む。
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .noSuitableRouteForCategory:
            restartAudioGraphAfterSystemChange()
        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        restartAudioGraphAfterSystemChange()
    }

    private func restartAudioGraphAfterSystemChange() {
        guard wantsRunning, !isInterrupted else { return }

        restartGeneration += 1
        let generation = restartGeneration
        stopAudioGraph(deactivateSession: false)
        attemptRestart(remainingDelays: restartRetryDelays, generation: generation)
    }

    /// 再起動を bounded retry で試みる。`.ended` / route 変更直後は HAL が落ち着くまで一時的に
    /// 失敗しやすいため、短い delay を挟んで数回試す。retry を使い切ってから `onStopped` で
    /// UI に通知する(旧実装は 1 回失敗で observer/wantsRunning を捨て、transient な失敗を
    /// 恒久エラー化していた)。`restartGeneration` で新しい停止/起動/再起動に追い越されたら破棄。
    private func attemptRestart(remainingDelays: [Swift.Duration], generation: Int) {
        guard generation == restartGeneration, wantsRunning, !isInterrupted else { return }

        do {
            try startAudioGraph()
            resetNotificationObserversForCurrentGeneration()
        } catch {
            guard let nextDelay = remainingDelays.first else {
                // bounded retry を使い切った: 失敗を握り潰さず UI に上げ、手動「もう一度」に委ねる。
                let pitchError = (error as? PitchEngineError) ?? .engineUnavailable
                wantsRunning = false
                removeNotificationObservers()
                onStopped?(pitchError)
                return
            }
            // observer / wantsRunning は維持し(後続の system event でも自己回復できる)、
            // 短い delay 後に再試行する。
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: nextDelay)
                guard let self else { return }
                self.attemptRestart(remainingDelays: Array(remainingDelays.dropFirst()), generation: generation)
            }
        }
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
