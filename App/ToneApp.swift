import SwiftUI
import ToneCore
import ToneAudio
import ToneUI

/// app shell: 具象(AudioKitPitchEngine / UserDefaultsReferencePitchStore / MonotonicClock)を
/// 注入した `TunerViewModel` を構築し、`TunerScreen` を表示するだけの薄い層。
@main
struct ToneApp: App {
    @State private var model = ToneApp.makeModel()

    var body: some Scene {
        WindowGroup {
            TunerScreen(model: model)
        }
    }

    @MainActor
    private static func makeModel() -> TunerViewModel {
        let engine: any PitchEngine
        let toneGenerator: any ToneGenerator
        #if DEBUG
        // デモ / スクショ時は AudioKit を構築せず疑似実装を使う。これにより起動時の
        // マイク権限ダイアログ(AudioKit のセッション要求)が出ず、UI だけを撮れる。
        if CommandLine.arguments.contains("--tone-demo")
            || CommandLine.arguments.contains("--fork-demo") {
            engine = DemoPitchEngine()
            toneGenerator = SilentToneGenerator()
        } else {
            engine = AudioKitPitchEngine()
            toneGenerator = AudioKitToneGenerator()
        }
        #else
        engine = AudioKitPitchEngine()
        toneGenerator = AudioKitToneGenerator()
        #endif

        let model = TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter()),
            store: UserDefaultsReferencePitchStore(),
            clock: MonotonicClock(),
            toneGenerator: toneGenerator,
            timbreStore: UserDefaultsToneTimbreStore()
        )

        #if DEBUG
        // `--fork-demo` で FORK モード起動 + `--fork-timbre=<name>` で音色プリセット
        // (音色選択 UI のスクショ用 / 本番ビルド非混入)。
        if CommandLine.arguments.contains("--fork-demo") {
            model.enterToneMode()
            if let timbre = CommandLine.arguments
                .first(where: { $0.hasPrefix("--fork-timbre=") })
                .map({ $0.dropFirst("--fork-timbre=".count) })
                .flatMap({ ToneTimbre(rawValue: String($0)) }) {
                model.selectToneTimbre(timbre)
            }
        }
        #endif

        return model
    }
}
