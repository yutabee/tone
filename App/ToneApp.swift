import SwiftUI
import ToneCore
import ToneAudio
import ToneUI

/// app shell: 具象(AudioKitPitchEngine / UserDefaultsReferencePitchStore / MonotonicClock)を
/// 注入した `TunerViewModel` を構築し、`TunerScreen` を表示するだけの薄い層。
@main
struct ToneApp: App {
    @State private var model = TunerViewModel(
        engine: AudioKitPitchEngine(),
        processor: TuningProcessor(converter: NoteConverter()),
        store: UserDefaultsReferencePitchStore(),
        clock: MonotonicClock()
    )

    var body: some Scene {
        WindowGroup {
            TunerScreen(model: model)
        }
    }
}
