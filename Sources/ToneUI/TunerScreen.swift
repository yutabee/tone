import SwiftUI
import Combine
import ToneCore
#if canImport(UIKit)
import UIKit
#endif

/// 1 画面チューナーのルートビュー。`TunerViewModel` を観測し、状態に応じて中央の表示を切り替える。
/// engine 非依存(ViewModel は app shell が具象注入する)。
public struct TunerScreen: View {
    private let model: TunerViewModel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 120
    @State private var hasStarted = false

    private let copy = TunerCopy()
    private let silenceTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public init(model: TunerViewModel) {
        self.model = model
    }

    private var theme: ToneTheme { ToneTheme(scheme: scheme, contrast: contrast) }

    /// 筐体上の発光(in-tune の signature)を許可する条件。筐体は常に dark なので scheme には
    /// 依らず、標準コントラスト / 透明度を減らさない場合のみ灯す。
    private var deviceGlow: Bool { theme.prefersGlow && !reduceTransparency }

    public var body: some View {
        ZStack {
            background

            center
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        // ロックの瞬間にハプティクスで“はまった”手応えを返す(主流の iOS 体験)。
        .sensoryFeedback(trigger: isInTune) { _, now in now ? .success : nil }
        .task {
            await model.onAppear()
            hasStarted = true
        }
        .onDisappear { model.onDisappear() }
        .onReceive(silenceTick) { _ in model.evaluateSilence() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.onDisappear()
            case .active where hasStarted: Task { await model.retry() }
            default: break
            }
        }
    }

    private var isInTune: Bool {
        if case let .tuning(_, inTune) = model.state { return inTune }
        return false
    }

    // MARK: - Background(色付きグラデ + 滲む光)

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [theme.bgTop, theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            if !reduceTransparency {
                RadialGradient(
                    colors: [theme.haloPrimary.opacity(theme.isDark ? 0.45 : 0.22), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 460
                )
                RadialGradient(
                    colors: [theme.haloSecondary.opacity(theme.isDark ? 0.40 : 0.18), .clear],
                    center: .bottomLeading, startRadius: 0, endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Faceplate(筐体)

    /// グラファイトの筐体。上=明 / 下=暗のブラッシュド面、外周の面取り、四隅のネジ、落ち影。
    /// reduce-transparency でも筐体は不透明な塗りなのでそのまま成立する(影だけ畳む)。
    private func faceplate<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        return content()
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape.fill(
                    LinearGradient(colors: [theme.faceTop, theme.faceBottom],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [theme.bezelHighlight, theme.bezelShadow],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5
                )
            }
            .overlay(alignment: .topLeading) { screw }
            .overlay(alignment: .topTrailing) { screw }
            .overlay(alignment: .bottomLeading) { screw }
            .overlay(alignment: .bottomTrailing) { screw }
            .shadow(color: reduceTransparency ? .clear : Color.black.opacity(0.5),
                    radius: reduceTransparency ? 0 : 32, y: reduceTransparency ? 0 : 20)
            .frame(maxWidth: 560)
    }

    /// 筐体角のネジ(マイナス溝)。装飾だが「機材」の記号として効く。VoiceOver からは隠す。
    private var screw: some View {
        Circle()
            .fill(
                RadialGradient(colors: [theme.screw, Color.black.opacity(0.7)],
                               center: .topLeading, startRadius: 0, endRadius: 7)
            )
            .frame(width: 9, height: 9)
            .overlay(
                Capsule().fill(Color.black.opacity(0.5))
                    .frame(width: 6, height: 1.2)
                    .rotationEffect(.degrees(45))
            )
            .padding(13)
            .accessibilityHidden(true)
    }

    /// 計器窓(recessed)。針メーターを沈める。in-tune で signal の微かな色味が乗る。
    private func meterWindow<Content: View>(tinted: Bool, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return content()
            .background {
                shape.fill(
                    LinearGradient(colors: [theme.meterFaceTop, theme.meterFaceBottom],
                                   startPoint: .top, endPoint: .bottom)
                )
                if tinted {
                    shape.fill(theme.signal.opacity(0.10))
                }
            }
            .overlay {
                // 上=暗 / 下=明 で「沈んだ」インセット感を出す。
                shape.strokeBorder(
                    LinearGradient(colors: [Color.black.opacity(0.55), Color.white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
    }

    /// 筐体上端の刻印行(ブランド + 種別)。
    private var faceplateHeader: some View {
        HStack {
            Text("TONE")
                .font(.system(size: 12, weight: .bold)).tracking(4)
            Spacer()
            Text("CHROMATIC")
                .font(.system(size: 10, weight: .semibold)).tracking(3)
        }
        .foregroundStyle(theme.faceMuted)
        .accessibilityHidden(true)
    }

    private var showsReferenceControl: Bool {
        switch model.state {
        case .permissionDenied, .engineError: return false
        default: return true
        }
    }

    /// REF ステッパー(筐体下部)。− A440 Hz + を機材のラベル調で。
    private var referenceControl: some View {
        HStack(spacing: 14) {
            referenceButton(symbol: "minus", label: copy.lowerReference) {
                model.setReferenceA4(model.referenceA4 - 1)
            }
            Text(copy.reference(model.referenceA4))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(theme.needle)
                .monospacedDigit()
                .accessibilityLabel(copy.reference(model.referenceA4))
            referenceButton(symbol: "plus", label: copy.raiseReference) {
                model.setReferenceA4(model.referenceA4 + 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous).fill(Color.black.opacity(0.28))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func referenceButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.faceMuted)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Center (state switch)

    @ViewBuilder
    private var center: some View {
        switch model.state {
        case .idle:
            statusMessage(copy.starting)
        case .requestingPermission:
            statusMessage(copy.requestingPermission)
        case .listening:
            tuningLayout(note: nil, inTune: false)
        case let .tuning(note, inTune):
            tuningLayout(note: note, inTune: inTune)
        case .permissionDenied:
            permissionDenied
        case let .engineError(error):
            engineError(error)
        }
    }

    // MARK: - Tuning / listening

    private func tuningLayout(note: ResolvedNote?, inTune: Bool) -> some View {
        faceplate {
            VStack(spacing: 0) {
                faceplateHeader

                Spacer(minLength: 16)

                meterWindow(tinted: inTune) {
                    VStack(spacing: 4) {
                        NeedleGauge(cents: note?.cents, inTune: inTune, theme: theme)
                        HStack {
                            Text("\u{266D}")        // flat 端ラベル
                            Spacer()
                            Text("\u{266F}")        // sharp 端ラベル
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.faceMuted)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                }

                Spacer(minLength: 24)

                lcdReadout(note: note, inTune: inTune)

                Spacer(minLength: 22)

                ledRow(note: note, inTune: inTune)

                if showsReferenceControl {
                    Spacer(minLength: 24)
                    referenceControl
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: inTune)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(note: note, inTune: inTune))
    }

    /// 音名の LCD 読み取り部。検出時は bone、in-tune では signal に灯る。横に cents 値を添える。
    private func lcdReadout(note: ResolvedNote?, inTune: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(note?.name.displayText ?? "\u{2013}")    // – when no reading
                .font(.system(size: heroSize, weight: .semibold, design: .rounded))
                .foregroundStyle(inTune ? theme.signal : theme.needle)
                // in-tune の瞬間だけ二段の emissive bloom で signal が灯る。
                .shadow(color: theme.signal.opacity(inTune && deviceGlow ? 0.42 : 0),
                        radius: inTune && deviceGlow ? 16 : 0)
                .shadow(color: theme.signal.opacity(inTune && deviceGlow ? 0.20 : 0),
                        radius: inTune && deviceGlow ? 34 : 0)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.18), value: inTune)

            if let octave = note?.octave {
                Text("\(octave)")
                    .font(.system(size: heroSize * 0.34, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.faceMuted)
                    .lineLimit(1)
            }

            Text(note.map { String(format: "%+d\u{00A2}", $0.cents) } ?? "")
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.faceMuted)
                .padding(.leading, 4)
        }
        .accessibilityHidden(true)
    }

    /// LED 列: ♭(amber) ─ IN TUNE(signal) ─ ♯(amber)。状態に応じて 1 つだけ灯る。
    private func ledRow(note: ResolvedNote?, inTune: Bool) -> some View {
        let cents = note?.cents
        let flatOn = note != nil && !inTune && (cents ?? 0) < 0
        let sharpOn = note != nil && !inTune && (cents ?? 0) > 0
        return HStack(spacing: 0) {
            led(label: copy.flat.uppercased(), on: flatOn, color: theme.ledAmber)
            Spacer()
            led(label: copy.inTune.uppercased(), on: inTune, color: theme.signal)
            Spacer()
            led(label: copy.sharp.uppercased(), on: sharpOn, color: theme.ledAmber)
        }
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }

    private func led(label: String, on: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? color : theme.ledOff)
                .frame(width: 8, height: 8)
                .shadow(color: on && deviceGlow ? color.opacity(0.85) : .clear,
                        radius: on && deviceGlow ? 5 : 0)
            Text(label)
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(on ? color : theme.faceMuted)
        }
        .animation(.easeInOut(duration: 0.18), value: on)
    }

    private func accessibilityDescription(note: ResolvedNote?, inTune: Bool) -> String {
        guard let note else { return copy.listening }
        return copy.noteAccessibilityLabel(note, inTune: inTune)
    }

    // MARK: - Other states

    private func statusMessage(_ text: String) -> some View {
        faceplate {
            VStack(spacing: 16) {
                faceplateHeader
                Text(text)
                    .font(.system(.body))
                    .foregroundStyle(theme.faceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 24)
            }
        }
    }

    private var permissionDenied: some View {
        messageBlock(title: copy.permissionTitle, body: copy.permissionBody, actionTitle: copy.openSettings) {
            openSystemSettings()
        }
    }

    private func engineError(_ error: PitchEngineError) -> some View {
        let body = error == .inputUnavailable ? copy.inputUnavailableBody : copy.engineErrorBody
        return messageBlock(title: copy.engineErrorTitle, body: body, actionTitle: copy.retry) {
            Task { await model.retry() }
        }
    }

    private func messageBlock(title: String, body: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        faceplate {
            VStack(spacing: 16) {
                faceplateHeader
                Text(title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(theme.needle)
                    .multilineTextAlignment(.center)
                Text(body)
                    .font(.system(.subheadline))
                    .foregroundStyle(theme.faceMuted)
                    .multilineTextAlignment(.center)
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(theme.faceBottom)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(theme.needle, in: Capsule(style: .continuous))
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
