# Spec: 音叉モード(リファレンストーン生成)

- Status: confirmed
- Date: 2026-06-21
- Issue: #(未作成)

## Goal (1 文)
Tone に、基準ピッチ(REF = A4)に基づくクロマチック 12 音の純音を再生する「音叉モード」を追加する。

## 背景 / 動機
現状の Tone は入力(マイク)→ ピッチ検出専用で、音を「出す」手段を持たない。耳合わせ・無音環境でのチューニング・基準音の提示には参照トーンの再生が要る。物理音叉の役割をアプリ内で担い、検出と同じ基準ピッチ(`referenceA4` 415–466Hz)で 12 音 × 複数オクターブを鳴らせるようにする。

## 設計判断 (mini-ADR)

### 判断1: トーン出力の抽象化 — 新規 `ToneGenerator` protocol を ToneCore に置く
- 代替A: ToneAudio に生成ロジックを直接実装(protocol なし)。利点: 層が薄い / 欠点: ToneCore から mock できず macOS test 不能、ToneUI が ToneAudio に依存しかねず層境界が崩れる。
- 代替B(採用): `PitchEngine` と対称な `ToneGenerator` protocol を ToneCore に定義し、AudioKit 実装を ToneAudio に置く。利点: 既存パターンと一致 / mock 注入で全状態遷移を macOS test 可能 / ToneCore は AudioKit 非依存を維持 / 欠点: 型が1つ増える。
- 採用理由: 既存の `PitchEngine` 注入アーキテクチャと完全対称で、テスト可能性と層境界の不変条件(ToneCore は純粋)を守れる。

### 判断2: 排他切替の調整役 — `TunerViewModel` を拡張する(別 VM を作らない)
- 代替A(採用): `TunerViewModel` に mode / トーン選択状態を足し、`ToneGenerator` を注入する。利点: 検出停止↔トーン開始の排他切替を単一 MainActor 調整役が所有 / 欠点: VM が太る。
- 代替B: `ToneGeneratorViewModel` を分離し親 coordinator で束ねる。利点: 関心分離 / 欠点: 2 VM が同一オーディオセッションを取り合う調整を別途要し、この規模では間接層が増えるだけ。
- 採用理由: ユーザ確定の「排他モード」では検出停止とトーン開始は不可分の 1 操作。単一の調整役に集約するのが最小で安全。

### 判断3: 音声セッション戦略 — 排他 `.playback`(ユーザ確定)
- トーン再生中は検出を止め、`AVAudioSession` を `.record`/`.measurement` から `.playback` へ切替。
- 採用理由(ユーザ確定): 同時動作はマイクが自分の再生音を拾うフィードバックループとセッション衝突を招く。排他なら `.playback` 単純化でフィードバックなし。実機チューナーの一般動作。

### 判断4: 音名→周波数 — ToneCore の純関数(`NoteConverter` と平均律式を共有)
- `ToneSelection.frequency(referenceA4:)` を ToneCore に純関数として置く。`NoteConverter`(freq→note)の逆で、同じ平均律式 `referenceA4 · 2^((midi-69)/12)` を使い基準ピッチへ追従させる(単一の音律ソース)。

### 判断5: 波形 — サイン波のみ(MVP)
- 代替: ノコギリ波/オルガン等の倍音付与で可聴性を上げる。
- 採用: 純音(サイン)。理由: 「音叉」の文字通りの実装で最小。可聴性が劣る点は端末音量で補う。倍音音色は Out of scope(後続で追加可)。

### 判断6: lifecycle 整合 — `startEngine()` / reading / silence を mode でゲートする
- 問題: 既存の検出エンジン lifecycle(`onAppear` の `startEngine`、scenePhase active 復帰の `retry()`、late reading の `handle()`、timer tick の `evaluateSilence()`)は mode を知らない。tone モード中にこれらが走ると検出エンジンが再起動し、排他 `.playback` を破る/state を書き換える。
- 代替A: 各 call site(UI 側 scenePhase など)で個別に mode 判定する。欠点: ガードが分散し漏れる。実機 lifecycle の経路追加ごとに再発する。
- 代替B(採用): `TunerViewModel` 内に **単一の不変条件**を置く — `startEngine()` / `handle()` / `evaluateSilence()` は `mode == .tone` の間 early-return する。`retry()` も `startEngine()` 経由なので自動的にゲートされる。
- 採用理由: 排他の保証点を VM の 1 か所に集約でき、UI 側に lifecycle 経路が増えても破れない(F5/F6 の根治)。

### 判断7: 再生状態の同期 — `ToneGenerator.onStopped` callback で `isTonePlaying` をハード追従させる
- 問題: 割り込み/route 喪失/media reset でハードが停止しても `isTonePlaying==true` が残ると、その後の `selectToneNote` / `adjustToneOctave` / `setReferenceA4` が「再生中」とみなして `play()` を再実行し、意図せず再発音する(「再生は復帰させない」と矛盾)。
- 代替A(旧 MVP): 同期せず「次のトグルで整合」。欠点: 上記の意図しない再発音が起き、トグルも 1 回目が空振りする実バグ。
- 代替B(採用): `ToneGenerator` に `onStopped: (@MainActor (StopReason) -> Void)?` を設け、非ユーザ要因の停止で VM が `isTonePlaying=false` を同期する。`stop()` 由来の停止では呼ばない(二重処理回避)。
- 採用理由: shadow state のズレを構造的に消す。protocol 1 プロパティの追加で済み、層境界も保つ。

### 判断8: クリック/グリッチ対策 — start/stop と周波数更新に短い ramp を通す
- 問題: `play(frequency:)` の即時周波数ジャンプ・start/stop の振幅不連続はクリックノイズになる。
- 採用: oscillator の start/stop に 5〜10ms の amplitude envelope、再生中の周波数更新に parameter ramp を通す。理由: 純音ゆえ不連続が目立つ。AudioKit の ramp 機能で最小実装可。

## 公開 Interface

### ToneCore(新規)
```swift
/// トーン生成器の致命的エラー(play が throw する理由)。
public enum ToneGeneratorError: Error, Equatable, Sendable {
    /// AVAudioEngine 起動失敗 / セッション有効化失敗 / media reset。
    case engineUnavailable
    /// frequency が <= 0 / NaN / inf。
    case invalidFrequency
}

/// 非ユーザ要因で再生が止まった理由(onStopped に渡す)。UI には出さないが
/// VM のテスト・将来のログ・分岐のために区別する。
public enum ToneGeneratorStopReason: Equatable, Sendable {
    case interruption        // 電話等の AVAudioSession interruption
    case routeChange         // 出力経路喪失(ヘッドフォン抜け等)
    case mediaServicesReset
}

/// 純音生成器の抽象(差替 / モック注入点)。マイク権限は不要(出力のみ)。
@MainActor
public protocol ToneGenerator: AnyObject {
    /// 非ユーザ要因(interruption / routeChange / mediaServicesReset)で再生が止まった時に
    /// 呼ばれる。VM が isTonePlaying=false を同期するために使う。
    /// stop() 由来の停止では呼ばない(二重処理回避)。
    var onStopped: (@MainActor (ToneGeneratorStopReason) -> Void)? { get set }
    /// 指定周波数の純音再生を開始する。再生中の呼び出しは周波数を更新する(冪等な再設定)。
    /// frequency が非正/非有限なら ToneGeneratorError.invalidFrequency を throw する。
    func play(frequency: Double) throws
    /// 停止。冪等。stop 後は無音。onStopped は呼ばない。
    func stop()
}

/// 鳴らす音の選択(音名 + 科学的音高オクターブ)。
public struct ToneSelection: Equatable, Sendable {
    public let name: NoteName
    public let octave: Int
    /// octave は ToneRange [minOctave, maxOctave] 内を前提とするが、init はクランプせず
    /// 与えられた値を保持する(範囲保証は adjustToneOctave 側の責務)。
    public init(name: NoteName, octave: Int)
    /// MIDI 番号: (octave + 1) * 12 + name のセミトーン index(C=0)。A4 → 69。
    public var midi: Int { get }
    /// 平均律周波数: referenceA4 * 2^((midi - 69) / 12)。
    /// referenceA4 は呼び出し側で 415–466 にクランプ済みを前提(非正/非有限は渡さない)。
    public func frequency(referenceA4: Double) -> Double
}

/// 音叉モードの定数。
public enum ToneRange {
    public static let minOctave: Int = 2          // C2 (midi 36)
    public static let maxOctave: Int = 6          // B6 (midi 95)
    public static let defaultSelection = ToneSelection(name: .A, octave: 4)
}
```

### ToneCore: `TunerViewModel` への追加
```swift
public enum Mode: Equatable { case tuner, tone }

public private(set) var mode: Mode               // 既定 .tuner
public private(set) var toneSelection: ToneSelection  // 既定 ToneRange.defaultSelection
public private(set) var isTonePlaying: Bool      // 既定 false

// init に generator を追加(既存 4 引数の末尾に追加):
public init(
    engine: any PitchEngine,
    processor: TuningProcessor,
    store: any ReferencePitchStore,
    clock: any Clock,
    toneGenerator: any ToneGenerator
)

/// 音叉モードへ入る: 検出を止め(engine.stop)、トーンは停止状態、mode=.tone。
/// 以後 startEngine/handle/evaluateSilence は mode==.tone の間ゲートされる(判断6)。
public func enterToneMode()
/// 音叉モードを出る: トーン停止 → mode=.tuner → 保持した permission 状態で分岐(挙動仕様参照)。
public func exitToneMode() async
/// 現在の選択でトーンを開始/停止する(トグル)。mode==.tone のときのみ作用。
public func toggleTone()
/// 鳴らす音名を変更。再生中なら周波数を即時更新する。mode==.tone のときのみ作用。
public func selectToneNote(_ name: NoteName)
/// オクターブを delta 分動かし [minOctave, maxOctave] にクランプ。再生中なら周波数を即時更新。
public func adjustToneOctave(_ delta: Int)
```

`startEngine()`(private)・`handle(_:)`・`evaluateSilence()` は `mode == .tone` の間 early-return する(判断6)。`retry()` は `startEngine()` 経由のため同様にゲートされる。`init` で `toneGenerator.onStopped` を設定し、非ユーザ要因停止で `isTonePlaying=false` を同期する(判断7)。

### ToneAudio(新規)
```swift
/// `ToneGenerator` の本番実装。AudioKit のオシレータ(サイン)で純音を出し、
/// AVAudioSession(.playback)のライフサイクル / 割り込み / route change / media reset を扱う。
/// 既存 `AudioKitPitchEngine` と同等の observer 世代管理で重複/競合を防ぐ。
/// interruption / routeChange(出力経路喪失) / mediaServicesReset を検知したら
/// 再生を止め `onStopped(reason)` を発火する(再生は自動復帰しない)。
/// start/stop に 5〜10ms envelope、周波数更新に parameter ramp を通しクリックを抑制する(判断8)。
@MainActor
public final class AudioKitToneGenerator: ToneGenerator { /* onStopped/play/stop */ }
```

### ToneUI(音叉モード画面)
```swift
/// モード切替トグル(.tuner ⇄ .tone)。
/// 音名選択(12 音)・オクターブ ∓・再生トグルを TunerViewModel に束ねる。
struct ToneModeView: View {                       // 内部 struct(public 不要)
    @ObservedObject var model: TunerViewModel
    // 音名タップ → model.selectToneNote(_:)
    // ∓ → model.adjustToneOctave(±1)
    // 再生ボタン → model.toggleTone()
}
```

## 挙動仕様

### 状態遷移表(mode × lifecycle イベント)
排他の保証点は判断6 の不変条件(`startEngine`/`handle`/`evaluateSilence` を `mode==.tone` でゲート)。下表はその帰結を網羅する。

| イベント | mode==.tuner | mode==.tone |
|---|---|---|
| `onAppear()` | 既存通り requestPermission → startEngine | startEngine がゲートされ検出を開始しない(tone は停止状態) |
| `enterToneMode()` | `engine.stop()`、`mode=.tone`、`isTonePlaying=false` | no-op |
| `exitToneMode()` | no-op | tone stop → `mode=.tuner` → permission 状態で分岐(下記) |
| `toggleTone()` | no-op | 再生/停止トグル |
| `selectToneNote`/`adjustToneOctave` | no-op | 選択更新(+再生中は周波数追従) |
| `setReferenceA4` | クランプ・保存・processor 再構築 | 同左 +再生中は新 REF で周波数追従 |
| scenePhase→background(`onDisappear`) | `engine.stop()` | `toneGenerator.stop()`、`isTonePlaying=false`(復帰時に自動再生しない) |
| scenePhase→active(`retry`) | 検出エンジン再開 | ゲートされ再開しない(`mode==.tone` 維持、tone も自動再開しない) |
| reading 到来(`handle`) | state 更新 | ゲートされ state 不変 |
| silence tick(`evaluateSilence`) | silence 評価 | ゲートされ state 不変 |
| `onStopped(reason)` | (tone 未使用) | `isTonePlaying=false` に同期 |

### 各メソッド
- **enterToneMode()**: `engine.stop()` を呼ぶ。`isTonePlaying=false`、`mode=.tone`。トーンは自動再生しない(ユーザのトグル待ち)。マイク権限状態に依らず実行可(出力のみ)。`onAppear` の permission await 中に呼ばれても、await 後の `startEngine()` は判断6 のゲートで空振りする(後から mic が始まらない=F6 の根治)。
- **exitToneMode()**: 再生中なら `toneGenerator.stop()`、`mode=.tuner`。検出復帰は**保持した permission 状態**で分岐する(既存 `startEngine()` は granted 前提なので直接呼ばない):
  - `granted`: `startEngine()`(成功で `.listening`、失敗で `.engineError`)。
  - `denied`: `state=.permissionDenied`(再要求しない)。
  - `notDetermined`: `requestPermission()` → granted なら `startEngine()`、denied なら `.permissionDenied`。
  - `onAppear` 未完了の初期段(permission 未確定で起動直後): `state` を変えず、後続の `onAppear` 完了に委ねる。
- **toggleTone()**: `mode == .tone` のときのみ作用。
  - `isTonePlaying == false`: `toneGenerator.play(frequency: toneSelection.frequency(referenceA4:))` 成功で `isTonePlaying=true`。`play` が throw したら `isTonePlaying=false` のまま(再生不可)。
  - `isTonePlaying == true`: `toneGenerator.stop()`、`isTonePlaying=false`。
- **selectToneNote(name) / adjustToneOctave(delta) / setReferenceA4(hz) の play() throw 共通ポリシー**: `isTonePlaying` 中に新周波数で `toneGenerator.play(...)` を呼ぶ。**throw した場合は `isTonePlaying=false` にし、選択/REF の変更自体は保持する**(無音になるが選択状態は最新)。停止中(`isTonePlaying==false`)は選択/REF のみ更新し `play` を呼ばない。
- **adjustToneOctave**: `octave = clamp(octave + delta, minOctave, maxOctave)`。範囲端では据え置き(no-op 相当)。
- **setReferenceA4(hz)**: 既存どおりクランプ・保存・processor 再構築に加え、`mode==.tone && isTonePlaying` なら新 `referenceA4` で `toneGenerator.play(...)` を呼び鳴っている音を即追従させる(上記 throw ポリシー適用)。
- **ToneSelection.frequency**: `referenceA4 * pow(2, Double(midi - 69)/12)`。`midi = (octave+1)*12 + NoteName.allCases.firstIndex(of: name)!`。
- **割り込み(電話等) / route change(出力経路喪失) / media reset**: `AudioKitToneGenerator` が自身のセッション内で検知し再生を止め、`onStopped(reason)` を発火する(再生は自動復帰しない)。VM はこれを受けて `isTonePlaying=false` を同期する(判断7)。これにより停止後に select/adjust/setRef を触っても意図しない再発音は起きない。

## エッジケース
- **マイク権限拒否中に音叉モード**: 可能。`enterToneMode` は権限を要求しない。トーン出力は `.playback` で完結。退出時は `exitToneMode` の permission 分岐で `.permissionDenied` へ戻る(検出は再開しない)。
- **`onAppear` permission await 中に `enterToneMode`**: await 完了後の `startEngine()` は判断6 ゲートで空振り。mic は始まらない。
- **`mode==.tuner` で toggleTone/selectToneNote/adjustToneOctave 呼び出し**: no-op(モード不一致)。
- **オクターブ範囲端**: `adjustToneOctave(+1)` が `maxOctave` 超なら据え置き、`-1` が `minOctave` 未満なら据え置き。`ToneSelection.init` 自体はクランプしないが、VM 経由の操作は常に範囲内に保つ。
- **`ToneSelection.frequency` への異常 referenceA4**: 呼び出し側(VM)で 415–466 にクランプ済みのため NaN/inf/<=0 は渡らない。`AudioKitToneGenerator.play` は防御的に `invalidFrequency` を throw する(直接生成テスト用の保険)。
- **`play` の throw**: `isTonePlaying` を true にしない(再生中の更新で throw した場合は false に落とす)。UI はトグルが入らない(=エラー時は静音のまま)。MVP ではトーン再生エラー専用の画面状態は設けない。
- **再生中の割り込み / route 喪失 / media reset でハード停止**: generator が `onStopped(reason)` を発火し VM が `isTonePlaying=false` を同期する(判断7)。これにより 1 回のトグルで再生でき、停止後の select/adjust/setRef で意図しない再発音も起きない。再生の自動復帰はしない(ユーザが再度トグル)。
- **REF 変更を再生中に実施**: 鳴っている音が即新基準へ追従(無音ギャップを作らず `play` で周波数更新、ramp 経由)。
- **`toneSelection.frequency` の範囲**: C2(REF440 で約 65.4Hz)〜 B6(約 1976Hz)。可聴域内。

## 依存 / 前提
- 既存 `NoteName`(`PitchReading.swift`、`allCases` 順 = C..B = semitone index)を再利用。
- 既存平均律式は `NoteConverter.note(for:)` 内(`referenceA4 * pow(2, (midi-69)/12)`)と同一。`ToneSelection.frequency` で同式を使い音律を一致させる。
- ToneAudio は iOS 専用(`#if os(iOS)`)。AudioKit/SoundpipeAudioKit のオシレータを使用。macOS では `ToneAudioModule` 同様に未提供。
- App shell(`App/ToneApp.swift:31`)が `AudioKitToneGenerator` を注入。`#if DEBUG --tone-demo` 経路にも generator を渡す(デモ用に実 generator)。
- **テスト用 `MockToneGenerator`**(ToneCoreTests): `onStopped` を保持し、`play(frequency:)`/`stop()` の呼び出し回数・最後の frequency・`isPlaying` を記録。`play` を throw させるフラグ、`onStopped` を任意 reason で手動発火する `simulateStop(_:)` を持つ(AC12/onStopped 同期のテスト用)。`Tests/ToneCoreTests/TunerViewModelTests.swift:14` の `makeViewModel` helper で注入。
- ToneUI は ToneCore のみ依存(現状維持)。音叉 UI は `TunerViewModel` を観測。

## Migration / Rollback
- N/A(新規機能・既存データ構造の移行なし)。
- `TunerViewModel.init` に `toneGenerator` 引数が増えるため **App shell と ToneCoreTests の全 init 呼び出しを更新**(破壊的変更だが追加のみ)。
- Rollback: `mode`/`toneSelection`/`isTonePlaying`/tone メソッドと `ToneGenerator` 注入・新ファイルを削除すれば旧挙動へ戻る。永続化を足さないため UserDefaults 互換性問題なし。

## 非要件 / Out of scope
- サイン波以外の音色 / 倍音 / 音色選択。
- 再生と検出の同時動作(`.playAndRecord`)。
- アプリ内音量スライダー(端末音量に委ねる)。
- 最後に鳴らした音の永続化(起動毎に A4 へ既定)。
- 押下中のみ発音 / 自動フェードアウト(トグルを採用)。
- A440 単音モード / 楽器プリセット(クロマチック12音を採用)。
- 割り込み/route/media reset からの**トーン自動再開**(`isTonePlaying` のハード同期は判断7 で行うが、再生自体は復帰させずユーザの再トグル)。
- トーン再生エラー専用の画面状態(MVP は静音のまま、エラー画面なし)。

## 受け入れ基準
ToneCore(macOS `swift test`、純粋部分):
- AC1 `ToneSelection(name:.A, octave:4).frequency(referenceA4: 440) == 440`(±1e-9)。
- AC2 `…referenceA4: 442 == 442`(REF 追従)。
- AC3 `ToneSelection(name:.C, octave:4).frequency(440)` ≈ 261.6256(±1e-3)。
- AC4 オクターブ +1 で周波数が 2 倍(A4 440 → A5 880、±1e-6)。
- AC5 `midi`: A4→69、C4→60、C2→36、B6→95。
ViewModel(mock `ToneGenerator`/`PitchEngine` 注入):
- AC6 `enterToneMode()` で `engine.stop()` が呼ばれ `mode==.tone`、`isTonePlaying==false`。
- AC7 `toggleTone()` 1 回で `generator.play(freq)` が選択 × referenceA4 の周波数で呼ばれ `isTonePlaying==true`、2 回目で `generator.stop()`・`isTonePlaying==false`。
- AC8 再生中 `selectToneNote(.C)` で `play` が C の新周波数で再呼び出しされる。停止中は `play` を呼ばない。
- AC9 `adjustToneOctave` が `[2,6]` にクランプ(B6 で +1 は据え置き、C2 で -1 は据え置き)。
- AC10 再生中 `setReferenceA4(442)` で `play` が新 REF の周波数で呼ばれる。
- AC11 `exitToneMode()` で `generator.stop()`(再生中なら)→ `granted` なら `engine.start()` 経路が走り `mode==.tuner`/`.listening`。
- AC12 `play` が throw する mock で `toggleTone()` を呼ぶと `isTonePlaying==false` のまま。
- AC13 `mode==.tuner` で `toggleTone()` は no-op(`play`/`stop` 未呼び出し)。
- AC14 **lifecycle ゲート(判断6)**: `mode==.tone` で `handle(reading)` を流しても `state` 不変、`evaluateSilence()` も `state` 不変、`retry()`/`startEngine()` で `engine.start()` が呼ばれない。
- AC15 **exitToneMode permission 分岐**: `granted`→`startEngine` 経路、`denied`→`.permissionDenied`(`engine.start` 未呼び出し)、`notDetermined`→`requestPermission` 後に分岐。
- AC16 **onStopped 同期(判断7)**: 再生中に `generator` の `simulateStop(.interruption)` を発火すると `isTonePlaying==false`。その後 `selectToneNote(.C)` を呼んでも `play` は呼ばれない(意図しない再発音なし)。
- AC17 **play throw 共通ポリシー**: 再生中に `play` を throw させた状態で `selectToneNote`/`adjustToneOctave`/`setReferenceA4` を呼ぶと `isTonePlaying==false`、かつ選択/REF は最新値を保持。
- AC18 `ToneSelection(name:.A, octave:4).frequency(referenceA4:)` は VM クランプ前提で正常値を返す。`AudioKitToneGenerator.play(frequency: 0/NaN/-1)` は `invalidFrequency` を throw(ToneAudio 単体、iOS)。
ToneAudio(iPhone 実機 手動 AC、`--tone-demo`):
- AC19 トグルで `.playback` セッションが張られ指定周波数の純音が鳴る/`stop` 後に無音。
- AC20 再生中の音名・オクターブ・REF 変更で**検出エンジンを再起動せず**、クリックノイズなく(ramp 経由で)周波数が変わる。
- AC21 通話着信(interruption)・ヘッドフォン抜き(routeChange)で再生が止まり、`isTonePlaying` が false に同期する(自動復帰しない)。
UI(iPhone シミュレータ目視、`--tone-demo`):
- AC22 モードトグルで音叉画面へ遷移し、音名選択・オクターブ ∓・再生トグルが表示される。
- AC23 既存 faceplate の適応スクロールにより大 Dynamic Type で要素が切れない。

## 分割計画
見込み diff: 約 400–480 行(ToneCore: protocol/StopReason/ToneSelection/VM 拡張+lifecycle ゲート+onStopped ~170、ToneAudio: AudioKitToneGenerator(observer 世代管理/ramp) ~150、ToneUI: 音叉画面 ~120、テスト ~120、App shell ~10)。レビュー反映で lifecycle/onStopped/AC が増え ~400 行をやや超えるため、**2 milestone に分割**(各 milestone で test→review):
- **M1(ToneCore 完結、単独 merge 可)**: `ToneGenerator`/`ToneSelection`/`ToneRange`/`ToneGeneratorStopReason` + 受け入れテスト(AC1–5)→ `TunerViewModel` 拡張(mode/lifecycle ゲート/onStopped/throw ポリシー)+ VM テスト(AC6–18)。
- **M2(iOS 実装 + UI)**: `AudioKitToneGenerator`(ramp/observer 世代管理/onStopped 発火)→ ToneUI 音叉画面 + モードトグル → App shell 注入 → 実機 AC19–21 / シミュレータ AC22–23。

## 未決事項
なし(確定)。
