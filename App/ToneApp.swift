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
        #if DEBUG
        if CommandLine.arguments.contains("--tone-demo") {
            engine = DemoPitchEngine()
        } else {
            engine = AudioKitPitchEngine()
        }
        #else
        engine = AudioKitPitchEngine()
        #endif

        return TunerViewModel(
            engine: engine,
            processor: TuningProcessor(converter: NoteConverter()),
            store: UserDefaultsReferencePitchStore(),
            clock: MonotonicClock()
        )
    }
}
