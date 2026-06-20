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
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 132
    @State private var hasStarted = false

    private let copy = TunerCopy()
    private let silenceTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public init(model: TunerViewModel) {
        self.model = model
    }

    private var theme: ToneTheme { ToneTheme(scheme: scheme, contrast: contrast) }

    /// 発光(in-tune の signature)を許可する条件: dark / 標準コントラスト / 透明度を減らさない。
    private var glowEnabled: Bool { theme.prefersDepthEffects && !reduceTransparency }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.paperTop, theme.paperBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                center
                Spacer(minLength: 0)
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, ToneMetrics.screenPadding)
            .padding(.vertical, ToneMetrics.screenPadding)
        }
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TONE")
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)

            Spacer()

            if showsReferenceControl {
                referenceControl
            }
        }
    }

    private var showsReferenceControl: Bool {
        switch model.state {
        case .permissionDenied, .engineError: return false
        default: return true
        }
    }

    private var referenceControl: some View {
        HStack(spacing: 14) {
            referenceButton(symbol: "minus", label: copy.lowerReference) {
                model.setReferenceA4(model.referenceA4 - 1)
            }
            Text(copy.reference(model.referenceA4))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.muted)
                .monospacedDigit()
                .accessibilityLabel(copy.reference(model.referenceA4))
            referenceButton(symbol: "plus", label: copy.raiseReference) {
                model.setReferenceA4(model.referenceA4 + 1)
            }
        }
    }

    private func referenceButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink)
                .frame(width: 32, height: 32)
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
        VStack(spacing: 28) {
            noteHero(note: note, inTune: inTune)
            centsReadout(note: note)
            CentsScale(cents: note?.cents, inTune: inTune, theme: theme)
            directionLabel(note: note, inTune: inTune)
        }
        .frame(maxWidth: 460)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(note: note, inTune: inTune))
    }

    private func noteHero(note: ResolvedNote?, inTune: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(note?.name.displayText ?? "\u{2013}")    // – when no reading
            .font(.system(size: heroSize, weight: .medium))
                .foregroundStyle(inTune ? theme.signal : theme.ink)
                // in-tune の瞬間だけ、深い背景に対して signal が灯る二段の emissive bloom。
                .shadow(color: theme.signal.opacity(inTune && glowEnabled ? 0.42 : 0),
                        radius: inTune && glowEnabled ? 16 : 0)
                .shadow(color: theme.signal.opacity(inTune && glowEnabled ? 0.20 : 0),
                        radius: inTune && glowEnabled ? 34 : 0)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.18), value: inTune)

            if let octave = note?.octave {
                Text("\(octave)")
                    .font(.system(size: heroSize * 0.34, weight: .regular))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
        }
    }

    private func centsReadout(note: ResolvedNote?) -> some View {
        Text(note.map { String(format: "%+d\u{00A2}", $0.cents) } ?? " ")
            .font(.system(.title3, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(theme.muted)
            .accessibilityHidden(true)
    }

    private func directionLabel(note: ResolvedNote?, inTune: Bool) -> some View {
        Text(directionText(note: note, inTune: inTune))
            .font(.system(size: 13, weight: .semibold))
            .tracking(2)
            .foregroundStyle(inTune ? theme.signal : theme.muted)
            .animation(.easeInOut(duration: 0.18), value: inTune)
            .accessibilityHidden(true)
    }

    private func directionText(note: ResolvedNote?, inTune: Bool) -> String {
        guard let note else { return copy.listening.uppercased() }
        if inTune { return copy.inTune.uppercased() }
        return (note.cents < 0 ? copy.flat : copy.sharp).uppercased()
    }

    private func accessibilityDescription(note: ResolvedNote?, inTune: Bool) -> String {
        guard let note else { return copy.listening }
        return copy.noteAccessibilityLabel(note, inTune: inTune)
    }

    // MARK: - Other states

    private func statusMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(.body))
            .foregroundStyle(theme.muted)
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
        VStack(spacing: 16) {
            Text(title)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(.subheadline))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(theme.paper)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(theme.ink, in: Capsule(style: .continuous))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 360)
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
