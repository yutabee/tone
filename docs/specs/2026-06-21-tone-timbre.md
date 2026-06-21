# Spec: 音叉モードの音色選択

- Status: confirmed
- Date: 2026-06-21
- Issue: #(未) — 確定後に create-issue

## Goal (1 文)
音叉モードで、ユーザが 4 種の音色(サイン / トライアングル / ノコギリ / 音叉=FM)から選んで基準音を鳴らせるようにし、選択は永続化・再生中変更は即反映する。

## 背景 / 動機
現状の音叉モードは `AudioKitToneGenerator` が `Oscillator`(既定=サイン波)固定で、倍音ゼロ・瞬時 on/off のため「電子音/機械音」に聞こえる。基準音としての正確さは保ちつつ、聞き取りやすい温かい音色を選べるようにしたい。基準ピッチ(referenceA4)が既に「選んで永続化し再生中即反映」できているのと同じ操作モデルを音色にも与える。

## 設計判断 (mini-ADR)

### D1. 音色セット — 採用: 波形3種 + FM 1種
- **案A 基本波形3種(sine/triangle/sawtooth)**: 利点=最小・アセット不要 / 欠点=まだ「シンセ」寄りで音叉らしさは弱い
- **案B 波形3種 + FM 1種(音叉/ベル系)** ✅: 利点=純音と温かい音叉音を両取り・アセット不要・依存追加なし(既存 SoundpipeAudioKit 内) / 欠点=FM のパラメータ調整が要る
- **案C 実楽器サンプル**: 利点=最も自然 / 欠点=SF2/音源アセットでバンドル増・ライセンス確認・実装大
- 採用理由: アセット/依存を増やさず「純音(基準) + 温かい音叉音」を提供でき、最小スペックと音質改善のバランスが最良。

### D2. 音色の表現箇所(アーキテクチャ) — 採用: ToneCore に純粋 enum、解釈は ToneAudio
- **案A ToneCore に `ToneTimbre` enum を置き、AudioKit ノードへの解釈は ToneAudio** ✅: 利点=ドメインが AudioKit 非依存のまま VM/UI/テストが enum を扱える(既存 `NoteName` 同型) / 欠点=enum 追加時に 2 層を触る
- **案B ToneAudio に音色を閉じ込め文字列で受け渡し**: 利点=ToneCore を触らない / 欠点=型安全性喪失・UI/VM が文字列を扱う・テスト困難
- 採用理由: 既存の `NoteName`/`ToneSelection` と同じ「純粋ドメイン型は ToneCore、音響解釈は ToneAudio」の分離を踏襲。amplitude 正規化値は音響レンダリングの詳細なので ToneAudio 側に保持しドメインを汚さない。

### D3. ToneGenerator の I/F 変更 — 採用: `play(frequency:timbre:)`
- **案A `play(frequency:timbre:)`(音色も毎回渡す)** ✅: 利点=frequency と同じく「毎回現在値を渡す」一貫モデル・呼び出し口が1つ / 欠点=protocol/モック/既存呼び出しを更新
- **案B `play(frequency:)` 据置 + `var timbre` プロパティ追加**: 利点=既存 play 呼び出し不変 / 欠点=状態が2経路(setter と play)に割れる・再生中変更の発火点が曖昧
- 採用理由: VM は既に `updatePlayingToneIfNeeded()` で「現在の選択で play を再呼び」しており、音色も同じ経路に乗せるのが最も単純。frequency と timbre を 1 回の play で原子的に渡せる。

### D5. 音色切替の AudioKit 内部設計 — 採用: 専用 `replaceVoice` 経路 + `currentTimbre` 状態機械
- **案A play() 内で stop()→start() を流用**: 利点=コード少 / 欠点=既存 `stop()` は session deactivate + observer removal を含むため、音色変更のたびに session を落として張り直し、observer 世代管理も曖昧になる。
- **案B 専用 `replaceVoice(timbre:frequency:)` 経路を切る** ✅: 利点=音色変更は「fade out → 旧ノード teardown → 新ノード rebuild → fade in」だけを行い、session/observer は維持。同一 timbre は ramp のみ。責務が `stop()`(完全停止)と分離する / 欠点=play() の分岐が一段増える。
- 採用理由: 既存実装は `private var oscillator: Oscillator?` 前提で `$frequency`/`$amplitude` を ramp している。FMOscillator は型も ramp 対象パラメータ(`$baseFrequency`)も異なるため、型差を play() 本体に cast で押し込むと散らかる。`currentTimbre` を保持し「同一 timbre=ramp / 異種 timbre=replaceVoice」を明確に分けるのが最小で安全。amplitude 正規化値も ToneAudio 内に閉じる(D2)。

### D4. 永続化 — 採用: 新 `ToneTimbreStore` protocol + UserDefaults
- **案A 設定ごとにストア(`ToneTimbreStore` を新設)** ✅: 利点=既存 `ReferencePitchStore` と同じ「1設定=1ストア」パターン踏襲・モック注入が容易 / 欠点=protocol/impl が1組増える
- **案B 汎用 KV ストアに統合**: 利点=ストアが1つ / 欠点=既存パターンから逸脱・既存ストアの移行が必要
- 採用理由: リポジトリの確立パターン(`ReferencePitchStore` + `UserDefaultsReferencePitchStore`)に揃える。最小の追加で一貫性を保つ。

## 公開 Interface

### ToneCore: `ToneTimbre.swift` (新規)
```swift
/// リファレンストーンの音色。純粋ドメイン型(AudioKit 非依存)。
public enum ToneTimbre: String, CaseIterable, Sendable {
    case sine
    case triangle
    case sawtooth
    case fork        // FM 合成による音叉/ベル系の温かい音

    /// 未保存 / 未知値からのフォールバック既定音色。
    public static let `default`: ToneTimbre = .sine
}
```
- UI 表示文言(短ラベル)と VoiceOver 読みは ToneUI(`TunerCopy`)側に置く。enum 自体は識別子のみ。

### ToneCore: `ToneTimbreStore` (新規 protocol)
```swift
/// 選択音色の永続化抽象(差替 / モック注入点)。
public protocol ToneTimbreStore: AnyObject {
    /// 保存済み音色。未保存 / 未知 rawValue は nil(呼出側が default にフォールバック)。
    func load() -> ToneTimbre?
    func save(_ timbre: ToneTimbre)
}
```

### ToneCore: `UserDefaultsToneTimbreStore.swift` (新規 impl)
```swift
public final class UserDefaultsToneTimbreStore: ToneTimbreStore {
    static let key = "tone.timbre"   // String rawValue を保存
    public init(defaults: UserDefaults = .standard)
    public func load() -> ToneTimbre?   // 未保存 or 未知 rawValue → nil
    public func save(_ timbre: ToneTimbre)
}
```

### ToneCore: `ToneGenerator` protocol (変更)
```swift
@MainActor
public protocol ToneGenerator: AnyObject {
    var onStopped: (@MainActor (ToneGeneratorStopReason) -> Void)? { get set }
    /// 再生開始 / 再生中は周波数・音色を反映。非正 / 非有限 frequency は invalidFrequency を throw。
    func play(frequency: Double, timbre: ToneTimbre) throws   // ← timbre 追加
    func stop()
}
```

### ToneCore: `TunerViewModel` (変更・追加)
```swift
public private(set) var toneTimbre: ToneTimbre   // 現在の選択音色(init は .default、onAppear で復元)
public func selectToneTimbre(_ timbre: ToneTimbre)   // 音叉モード時のみ有効。永続化 + 再生中即反映

// init に timbreStore を追加注入(既存 store: ReferencePitchStore と名前衝突しないよう timbreStore: とする):
public init(
    engine: any PitchEngine,
    processor: TuningProcessor,
    store: any ReferencePitchStore,
    clock: any Clock,
    toneGenerator: any ToneGenerator,
    timbreStore: any ToneTimbreStore        // ← 追加(末尾)
)
```

### ToneUI: `TunerCopy` (追加)
```swift
func timbreLabel(_ timbre: ToneTimbre) -> String        // チップ表示(例 ja/en)
func timbreAccessibilityLabel(_ timbre: ToneTimbre) -> String   // VoiceOver
```

### ToneUI: 音色選択 UI(`ToneModeView` に追加)
- **配置**: 音叉モード(`ToneModeView`)の再生ボタンの**直上**に音色チップ列を置く(ユーザ確定)。チューナーモードでは非表示。
- **コンポーネント**: 横並びのチップ(`Button` + `Capsule`/`RoundedRectangle` 背景)。`octaveStepper`/`noteCell` と同系の trait。segmented control は使わない(4 要素 + ja/en ラベルで幅が割れるため)。
- **表示順**: `sine → triangle → sawtooth → fork` を**固定順で明示**する(`ToneTimbre.allCases` の宣言順に依存させず、UI 側に表示順配列を持つ。enum 順序変更が表示順に漏れない)。
- **選択状態**: 現在の `model.toneTimbre` と一致するチップを選択表示(`theme.needle` 塗り + `faceBottom` 文字、`noteCell` の選択中と同方式)。再生中はさらに `theme.signal` で点灯。
- **アクセシビリティ**: 各チップに `copy.timbreAccessibilityLabel(_:)`、選択中は `.isSelected` trait。
- **操作**: タップで `model.selectToneTimbre(_:)` を呼ぶ。
- **Dynamic Type**: 既存 faceplate の適応スクロール下で大サイズでも切れない(チップは折返しか横スクロールを許容)。

## 挙動仕様
- **初期化(2 段)**: 既存 `referenceA4` の復元タイミングに揃える。
  - `init`: `toneTimbre = ToneTimbre.default`(=sine)。ストアアクセスはしない。再生もしない。
  - `onAppear()`: 既存の `store.load()`(referenceA4)と同じ箇所で `timbreStore.load()` を呼び、`nil` なら `default`、それ以外で復元。これにより「復元タイミングが referenceA4=onAppear / timbre=init」と分裂しない。
- **音色選択 `selectToneTimbre(t)`**:
  - `mode != .tone` のとき: no-op(`adjustToneOctave` 等と同じガード)。
  - `mode == .tone` のとき: `toneTimbre = t` → `timbreStore.save(t)` → `updatePlayingToneIfNeeded()`(再生中なら新音色で `play` 再呼び、停止中は状態のみ更新)。
- **再生**: `playSelectedTone()` は `toneGenerator.play(frequency: 選択周波数, timbre: toneTimbre)` を呼ぶ。throw 時は既存ポリシー通り `stop()` + `isTonePlaying=false`。
- **再生中の音色変更(AudioKitToneGenerator)**: `play` 内で「frequency のみ変化 → 既存どおり ramp」「timbre が現在と異なる → graph を fade で停止し新ノードで再構築・fade in」。クリック音は既存の envelope(`envelopeDuration`)で回避。
- **音量正規化(AudioKitToneGenerator)**: 音色ごとに目標 amplitude を保持し知覚音量を揃える(近似初期値 sine 0.2 / triangle 0.18 / sawtooth 0.13 / fork 0.16、実装時に実測調整)。`targetAmplitude` 定数を音色別マップに置換。
- **音色→ノード対応(AudioKitToneGenerator)**:
  - sine/triangle/sawtooth → `Oscillator(waveform: Table(.sine/.triangle/.sawtooth))`、`frequency` = 要求 frequency。
  - fork → `FMOscillator`。**音高保証**: 要求 frequency を `baseFrequency` に対応させ、`carrierMultiplier = 1.0` とすることでキャリアが要求 frequency と一致(= 基準音として正確に鳴る)。倍音付与は `modulatingMultiplier ≈ 2.0` / `modulationIndex ≈ 1〜3`(ベル/音叉的な軽い倍音、実装時に実測調整)。`amplitude` は音量正規化値(下記)。
  - **周波数変更(同一 timbre)**: Oscillator は `$frequency`、FMOscillator は `$baseFrequency` を ramp する(ramp 対象パラメータが型で異なる)。

## エッジケース
- **未知 rawValue の復元**: 旧版で保存→将来 case 削除等で `ToneTimbre(rawValue:)==nil` → `load()` は nil → default(sine) にフォールバック(クラッシュしない)。
- **停止中の音色変更**: `isTonePlaying==false` なら `updatePlayingToneIfNeeded()` は no-op、状態と永続化のみ更新。次回 Play で反映。
- **同一音色の再選択**: `selectToneTimbre(現在値)` は save + (再生中なら)play 再呼びが走るが冪等(音は途切れない範囲。再生中の同一音色再選は frequency 同一なら実質 no-op の ramp)。
- **音色変更と同時の中断/route 変更**: 既存の世代ガード(`notificationGeneration`)と async teardown がそのまま適用(本変更は play 経路のみ拡張)。
- **チューナーモードでの音色操作**: UI 上は音色チップを音叉モードでのみ表示。VM 側も `mode != .tone` ガードで二重防御。
- **FMOscillator と Oscillator の型差**: 音色変更時はノード型が変わるため ramp 不可 → 必ず teardown+rebuild 経路を通る。

## 依存 / 前提
- 既存 `SoundpipeAudioKit`(`Oscillator` / `Table` / `FMOscillator`)・`AudioKit`(`AudioEngine`)。**依存追加なし**。
- 既存パターン: `ReferencePitchStore` + `UserDefaultsReferencePitchStore`(永続化)、`TunerViewModel.updatePlayingToneIfNeeded()`(再生中即反映)、`AudioKitToneGenerator` の envelope/世代ガード/async teardown。
- 既存 `NoteName.displayText`(ToneCore のドメイン表示文字列)パターンに倣うが、音色ラベルは UI 文言性が強いため `TunerCopy` 側に置く。

## Migration / Rollback
- **Migration**: 新規 UserDefaults キー `tone.timbre` のみ追加。既存ユーザはキー未保存 → default(sine) で**現状と同一挙動**。既存 `tone.referenceA4` には影響なし。
- **Rollback**: 機能を戻しても `tone.timbre` キーが残るだけで無害(読み手が消えれば無視される)。protocol signature を戻す場合は呼出箇所の戻しが必要。

## 非要件 / Out of scope
- 音色ごとのエンベロープ/ADSR の個別調整 UI、ビブラート、エフェクト(リバーブ等)。
- 実楽器サンプル/SF2 音源(案C)。
- 音色のプレビュー試聴 UI(選択=即時反映なので別途試聴は設けない)。
- チューナーモードへの音色概念の拡張(音叉モード専用)。
- 音色追加のための plugin 機構/動的ロード。

## 受け入れ基準 (VM レベル、モック generator で検証)
- AC-T1: `init` 直後(`onAppear` 前)は `toneTimbre == .sine`(= `.default`、ストア未アクセス)。
- AC-T2: `timbreStore.load()==nil` の状態で `onAppear()` 実行後 → `toneTimbre == .sine`。
- AC-T3: `timbreStore.load()==.fork` の状態で `onAppear()` 実行後 → `toneTimbre == .fork`。
- AC-T4: 音叉モードで `selectToneTimbre(.triangle)` → `toneTimbre==.triangle` かつ `timbreStore.save(.triangle)` が呼ばれる。
- AC-T5: 再生中に `selectToneTimbre(.sawtooth)` → generator.play が `timbre==.sawtooth` で再呼びされる(モックが最後の timbre を記録)。
- AC-T6: 停止中に `selectToneTimbre(.fork)` → generator.play は呼ばれず、`toneTimbre==.fork` と save のみ。
- AC-T7: `mode==.tuner` で `selectToneTimbre(.triangle)` → no-op(`toneTimbre` 不変・save 未呼び)。
- AC-T8: `playSelectedTone()` 成功時 generator.play に `timbre==現在の toneTimbre` が渡る。
- AC-T9: 再生中に現在と同一の `selectToneTimbre(現在値)` → `toneTimbre` 不変・save は呼ばれる(冪等)・play は再呼びされるが frequency/timbre が同一(音は途切れない)。
- AC-T10: 再生中に generator.play が throw する状態で `selectToneTimbre(.fork)` → 既存 play ポリシー通り `stop()` 相当 + `isTonePlaying==false`(例外が VM 外に漏れない)。
- AC-T11: `UserDefaultsToneTimbreStore` round-trip: save(.fork)→load()==.fork / 未保存→nil / 未知 rawValue→nil。
- AC-T12(手動・iOS、合否文): 以下を満たす。
  - (a) sine/triangle/sawtooth/fork の 4 音色がそれぞれ可聴で、隣接音色と聞き分けられる。
  - (b) 再生中に音色を切り替えてもクリック音 / 無音ギャップが知覚されない。
  - (c) fork が sine より倍音が多く「温かい」(主観だが a/b より緩い基準)。
  - (d) 各音色で A4(440Hz)を鳴らし、チューナー等で実測ピッチが 440±2Hz(基準音として正確)。
  - (e) 4 音色の知覚音量差が大きく崩れていない(正規化が効いている)。

## 分割計画
見込み diff ~300 行(ToneTimbre 30 / Store protocol+impl 50 / VM 25 / protocol+mock 20 / AudioKitToneGenerator 65 / ToneUI チップ 50 / TunerCopy 15 / tests 70)。**~400 行未満 → 単一マイルストーン**(分割不要)。自動テスト(AC-T1〜T11)を先行 commit してから実装委譲。AC-T12 は手動 iOS 検証。

## 未決事項
(なし — 確定可能)
