#if DEBUG
import Foundation
import ToneCore

/// デザイン確認 / プレビュー用の擬似 engine。一定周波数の reading を流して tuning 状態を再現する。
/// `--tone-demo` 起動引数のときだけ使われ、本番ビルド(`#if DEBUG`)には含まれない。
@MainActor
final class DemoPitchEngine: PitchEngine {
    var onReading: (@MainActor (PitchReading) -> Void)?

    private let frequency: Double
    private let clock: any Clock
    private var task: Task<Void, Never>?

    init(frequency: Double = 443.0, clock: any Clock = MonotonicClock()) {
        // `--tone-demo-hz=<value>` で周波数を上書き可(デザイン確認用)。
        let override = CommandLine.arguments
            .first { $0.hasPrefix("--tone-demo-hz=") }
            .flatMap { Double($0.dropFirst("--tone-demo-hz=".count)) }
        self.frequency = override ?? frequency
        self.clock = clock
    }

    func requestPermission() async -> PermissionState { .granted }

    func start() throws {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.onReading?(
                    PitchReading(frequency: self.frequency, amplitude: 0.5, timestamp: self.clock.now)
                )
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
#endif
