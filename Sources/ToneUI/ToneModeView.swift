import SwiftUI
import ToneCore

/// 音叉モードの操作面。音名選択(12 音)・オクターブ ∓・再生トグルを `TunerViewModel` に束ねる。
/// 筐体(faceplate)・モードトグル・REF ステッパーは親 `TunerScreen` が供給し、本ビューは
/// その内側の操作クラスタのみを描く。再生中は hero / 選択音名 / 再生ボタンに signal が灯る。
struct ToneModeView: View {
    let model: TunerViewModel
    let theme: ToneTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 84

    private let copy = TunerCopy()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let timbreOrder: [ToneTimbre] = [.sine, .triangle, .sawtooth, .fork]

    private var playing: Bool { model.isTonePlaying }
    private var selection: ToneSelection { model.toneSelection }
    private var frequency: Double { selection.frequency(referenceA4: model.referenceA4) }

    /// 筐体の発光(再生 signature)を許可する条件。TunerScreen の deviceGlow と同条件。
    private var deviceGlow: Bool { theme.prefersGlow && !reduceTransparency }

    var body: some View {
        VStack(spacing: 0) {
            hero

            Spacer(minLength: 18)

            noteGrid

            // grid と OCT を 1 つの選択クラスタとして近接させる(固定間隔)。
            Spacer().frame(height: 14)

            octaveStepper

            // 選択クラスタと主操作(再生)の間に主たる余白を置く(可変)。
            Spacer(minLength: 28)

            timbreChips

            Spacer().frame(height: 12)

            playButton
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: playing)
    }

    // MARK: - Hero(選択音 + 周波数)

    /// 選択中の音名 + オクターブ(大)と再生周波数(Hz)。再生中は signal の bloom が灯る。
    private var hero: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(selection.name.displayText)
                    .font(.system(size: heroSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(playing ? theme.signal : theme.needle)
                    .shadow(color: theme.signal.opacity(playing && deviceGlow ? 0.42 : 0),
                            radius: playing && deviceGlow ? 16 : 0)
                    .shadow(color: theme.signal.opacity(playing && deviceGlow ? 0.20 : 0),
                            radius: playing && deviceGlow ? 34 : 0)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("\(selection.octave)")
                    .font(.system(size: heroSize * 0.34, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.needle.opacity(0.7))
                    .lineLimit(1)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: playing)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", frequency))
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.needle)
                Text("Hz")
                    .font(.system(.caption2).weight(.medium))
                    .foregroundStyle(theme.faceMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.toneStatus(selection, frequency: frequency, playing: playing))
    }

    // MARK: - 音名選択(12 音)

    private var noteGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NoteName.allCases, id: \.self) { name in
                noteCell(name)
            }
        }
    }

    private func noteCell(_ name: NoteName) -> some View {
        let selected = name == selection.name
        let lit = selected && playing
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            model.selectToneNote(name)
        } label: {
            Text(name.displayText)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(selected ? theme.faceBottom : theme.needle)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    shape.fill(selected ? (lit ? theme.signal : theme.needle) : Color.black.opacity(0.24))
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(selected ? 0 : 0.06), lineWidth: 1)
                }
                .shadow(color: lit && deviceGlow ? theme.signal.opacity(0.6) : .clear,
                        radius: lit && deviceGlow ? 8 : 0)
                .contentShape(shape)
        }
        .accessibilityLabel(copy.toneNoteName(name))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - オクターブ ∓

    private var octaveStepper: some View {
        HStack(spacing: 14) {
            octaveButton(symbol: "minus", label: copy.lowerOctave,
                         enabled: selection.octave > ToneRange.minOctave) {
                model.adjustToneOctave(-1)
            }

            VStack(spacing: 2) {
                Text("OCT")
                    .font(.system(.caption2).weight(.semibold)).tracking(2)
                    .foregroundStyle(theme.faceMuted)
                Text("\(selection.octave)")
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.needle)
            }
            .frame(minWidth: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.octaveValue(selection.octave))

            octaveButton(symbol: "plus", label: copy.raiseOctave,
                         enabled: selection.octave < ToneRange.maxOctave) {
                model.adjustToneOctave(+1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous).fill(Color.black.opacity(0.28))
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func octaveButton(symbol: String, label: String, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? theme.faceMuted : theme.ledOff)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - 音色選択

    private var timbreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(timbreOrder, id: \.self) { timbre in
                    timbreChip(timbre)
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func timbreChip(_ timbre: ToneTimbre) -> some View {
        let selected = timbre == model.toneTimbre
        let lit = selected && playing
        let shape = Capsule(style: .continuous)
        return Button {
            model.selectToneTimbre(timbre)
        } label: {
            Text(copy.timbreLabel(timbre))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(selected ? theme.faceBottom : theme.needle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    shape.fill(selected ? (lit ? theme.signal : theme.needle) : Color.black.opacity(0.24))
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(selected ? 0 : 0.06), lineWidth: 1)
                }
                .shadow(color: lit && deviceGlow ? theme.signal.opacity(0.55) : .clear,
                        radius: lit && deviceGlow ? 8 : 0)
                .contentShape(shape)
        }
        .accessibilityLabel(copy.timbreAccessibilityLabel(timbre))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 再生トグル

    private var playButton: some View {
        Button {
            model.toggleTone()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(playing ? copy.stop : copy.play)
                    .font(.system(.body, weight: .semibold)).tracking(1)
            }
            .foregroundStyle(theme.faceBottom)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                Capsule(style: .continuous).fill(playing ? theme.signal : theme.needle)
            }
            .shadow(color: playing && deviceGlow ? theme.signal.opacity(0.5) : .clear,
                    radius: playing && deviceGlow ? 14 : 0)
            .contentShape(Capsule(style: .continuous))
        }
        .accessibilityLabel(playing ? copy.stop : copy.play)
    }
}
