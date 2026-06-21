import Foundation
@testable import ToneCore

/// テスト用 `ToneGenerator`。`play`/`stop` の呼び出し回数・最後の frequency・`isPlaying` を記録し、
/// `playError` で `play` を throw させ、`simulateStop(_:)` で非ユーザ要因停止(`onStopped`)を発火できる。
@MainActor
final class MockToneGenerator: ToneGenerator {
    var onStopped: (@MainActor (ToneGeneratorStopReason) -> Void)?

    /// `nil` でなければ `play(frequency:)` がこのエラーを throw する。
    var playError: ToneGeneratorError?

    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastFrequency: Double?
    private(set) var lastTimbre: ToneTimbre?
    private(set) var isPlaying = false

    func play(frequency: Double, timbre: ToneTimbre) throws {
        playCallCount += 1
        if let playError {
            throw playError
        }
        lastFrequency = frequency
        lastTimbre = timbre
        isPlaying = true
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
    }

    /// 割り込み / route 喪失 / media reset 相当の非ユーザ要因停止をシミュレートし `onStopped` を発火する。
    func simulateStop(_ reason: ToneGeneratorStopReason) {
        isPlaying = false
        onStopped?(reason)
    }
}
