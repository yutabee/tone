import Foundation
@testable import ToneCore

/// テスト用 `PitchEngine`。`requestPermission` の戻り値と `start()` の挙動を制御でき、
/// `emit(_:)` で `onReading` を手動発火して検出をシミュレートできる。
@MainActor
final class MockPitchEngine: PitchEngine {
    var onReading: (@MainActor (PitchReading) -> Void)?

    /// `requestPermission()` が返す値。
    var permissionResult: PermissionState = .granted
    /// `start()` が投げるエラー(`nil` なら成功)。
    var startError: PitchEngineError?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var permissionRequestCount = 0

    func requestPermission() async -> PermissionState {
        permissionRequestCount += 1
        return permissionResult
    }

    func start() throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCallCount += 1
    }

    /// `onReading` を手動発火する(検出フレーム到来をシミュレート)。
    func emit(_ reading: PitchReading) {
        onReading?(reading)
    }
}

/// テスト用 monotonic clock。`now` を直接進められる。
final class TestClock: Clock {
    var now: TimeInterval
    init(now: TimeInterval = 0) {
        self.now = now
    }
}

/// テスト用 in-memory 永続化。
final class InMemoryReferencePitchStore: ReferencePitchStore {
    private var stored: Double?
    init(initial: Double? = nil) {
        self.stored = initial
    }

    func load() -> Double? { stored }
    func save(_ hz: Double) { stored = hz }
}

/// テスト用 in-memory 音色永続化。`saveCallCount` で save 呼び出しを検証できる。
final class InMemoryToneTimbreStore: ToneTimbreStore {
    private(set) var stored: ToneTimbre?
    private(set) var saveCallCount = 0
    init(initial: ToneTimbre? = nil) {
        self.stored = initial
    }

    func load() -> ToneTimbre? { stored }
    func save(_ timbre: ToneTimbre) {
        stored = timbre
        saveCallCount += 1
    }
}
