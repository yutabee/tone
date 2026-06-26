# マイク起動失敗の原因監査 — "Couldn't use the microphone"

- 日付: 2026-06-26
- 対象: `ToneAudio` / `ToneCore` / `ToneUI` のマイク・`AVAudioSession`・権限・ライフサイクル経路
- 手法: 死角駆動レビュー 7 レンズ fan-out (permission / session / interruption / route / race / engine / lifecycle) → finding ごとに反証検証 → 完全性クリティック。**41 findings**。検証フェーズは API レート制限で 20 体が失敗したため、収束クラスタの最終判定は人間 (Claude) lens が突き合わせて確定。
- 既出 (本レポート対象外): エラー = `state .engineError(.engineUnavailable)`、throw 元は `AudioKitPitchEngine.startAudioGraph()` の 3 箇所、診断ログは別ブランチで追加済み。

## 結論 (root issue に統合)

| # | root issue | 種別 | 重大度 | 私の判定 | 表面化 | 報告 repro? |
|---|---|---|---|---|---|---|
| 1 | 初回許可付与 → 同一ターンで即 `startEngine()`、失敗しても自動 retry が無い (scenePhase `.active` retry は edge 既通過) | race/permission/lifecycle | **High** | 構造的に確実 (5レンズ一致 ★★★) | engineUnavailable | **○ 最有力** |
| 2 | 自動 restart (`restartAudioGraphAfterSystemChange` の `try?`) が失敗を握り潰し、ViewModel に伝わらず無音の死んだマイク | interruption/route/lifecycle | **High** | 確認 (★★★) | silent / frozen-ui | 隣接 |
| 3 | 割り込み `.ended` で `.shouldResume` 無し → `wantsRunning=false` で永久停止、UI へ通知なし | interruption/race | **High** | 確認 (★★) | frozen-ui | 隣接 |
| 4 | `PitchEngine` に `onStopped`/`onError` が無い (ToneGenerator にはある) — #2/#3 を UI に伝える経路が構造的に欠落 | protocol 設計 | **High** | 確認 (クリティック#1) | silent | 根本 |
| 5 | `.record` + `engine.output = 無音Mixer` がハードウェア出力へ render path を張る → `.record` は出力 route 無しのため `engine.start()` が実機で throw し得る | engine | **High (要ログ確認)** | 機構は AudioKit ソースで裏取り済、実機 throw は未確認 | engineUnavailable | 候補 |
| 6 | 持続的なマイク占有 (画面収録+マイク / ReplayKit / 録音アプリ / 通話) → `setActive` が IsBusy を投げ続け「Try again」が永久に失敗 | session/contention | **Med-High** | 確認 (クリティック#2、文言どおりの真因) | engineUnavailable | 候補 (審査落ち経路) |
| 7 | `retry()`/`.active`retry/`exitToneMode` が権限を再確認しない → 拒否状態を無音 `.listening` で上書き、または誤メッセージ | permission/lifecycle | **Med** | 確認 (★★、ただし iOS の revoke 時 app-kill で一部到達性低) | wrong-message | 隣接 |
| 8 | `.allowBluetoothHFP` + `.measurement` で AirPods/BT 接続時に 8/16kHz HFP mono へ → 検出劣化で「壊れている」体感 | route/session | **Med** | 確認 (★★) | degraded-detection | 別系統 |

### 反証で棄却 (対応不要)
- `lifecycle/cross-engine-deferred-deactivate-race` (refuted): iOS は busy なセッションの `setActive(false)` を拒否するため、無音キルは起きにくい (#9 参照で軽量化)。
- `session/no-preferred-samplerate-iobuffer` (refuted): preferred sample rate 未設定は問題ない。AVAudioEngine がフォーマットを解決する。
- `route/categorychange-skip-misses-cross-engine` (refuted): #9 に吸収。

### 別評価: クロスエンジン session レース (#9)
`AudioKitToneGenerator.stop()` は ~8ms 後に遅延 `setActive(false)` を発火し、独自の `notificationGeneration` しか見ない。`exitToneMode()` は直後に pitch engine を起動するため、遅延無効化が pitch のライブセッションに重なる。**ただし** iOS は稼働中セッションの `setActive(false)` を拒否 (例外は catch+log) する公算が高く、無音キルの実害は限定的 (= Med→Low へ降格)。それでも「共有 singleton を 2 つの所有者が独立世代で操作」する設計は脆く、所有権の一元化を推奨。報告 repro (初回・音叉未使用) には**該当しない**。

---

## 1. 報告された repro の機序 (最有力)

```
onAppear() → state=.requestingPermission
           → await engine.requestPermission()   // 初回は system dialog
   [ユーザ Allow タップ] → continuation resume (同一 main-actor ターン)
           → startEngine()                       // ← 即時・同期
                → startAudioGraph():
                     setCategory(.record,.measurement,[.allowBluetoothHFP])
                     setActive(true)              // 付与直後は HAL 未settle → throw 余地
                     engine.start()               // input format 0ch/0Hz の瞬間 → throw 余地
                → catch → state=.engineError(.engineUnavailable)
   onAppear() return → hasStarted=true            // ← retry の前提がここで初めて true
```

`scenePhase .active where hasStarted` の自動 retry (`TunerScreen.swift:53`) は **edge トリガ**。許可ダイアログ解除に伴う `.active` 遷移は `hasStarted=false` の間に既に通過済みのため、初回失敗を救えない。結果、ユーザは手動「もう一度」を押すまでエラーカードに固定 → 押すと HAL が settle 済で成功 = 「初回だけ失敗、再試行で通る」に一致。

**根拠**: `TunerViewModel.swift:85-98, 227-238` / `AudioKitPitchEngine.swift:57-73, 104-178` / `TunerScreen.swift:44-47, 50-56` / `TunerCopy.swift:35-39`

**対策 (推奨)**: `requestPermission()` が「undetermined→granted の新規付与か」を返すようにし、新規付与時のみ `startEngine()` を `[0, 150ms, 350ms]` のバックオフで bounded retry。`engine.start()` は同期なので、`Task.sleep` は async な `onAppear`/`startEngine` 側で行う。最終試行後にのみ `.engineError` を出し、手動「もう一度」は最終 fallback として維持。

---

## 2-4. 自動復帰の握り潰し + 通知経路の欠落 (構造)

- `restartAudioGraphAfterSystemChange()` は `try? startAudioGraph()` (`AudioKitPitchEngine.swift:299-305`)。route 変更 / interruption `.ended` / media reset 後の再起動が失敗しても **例外が消え、engine は死亡、ViewModel は `.listening`/`.tuning` のまま**。
- 割り込み `.ended` で `.shouldResume` 無しのとき `wantsRunning=false` にして終了 (`:270-277`)、UI へ通知なし。
- 根本原因: **`PitchEngine` protocol に `onStopped`/`onError` が無い** (`PitchEngine.swift:21-31`)。`ToneGenerator` は `onStopped` を持つのに pitch 側は `onReading` のみ。System 由来の停止を UI が知る術がない。

**対策**: `PitchEngine` に `onStopped(PitchEngineError?)` 相当の callback を追加し、`restartAudioGraphAfterSystemChange()` の失敗と `.ended`(非resume)で発火 → ViewModel が `.engineError` へ遷移し「もう一度」を提示。これで #2/#3 がまとめて UI に可視化される。

---

## 5. `.record` + 無音出力 mixer の `engine.start()` 失敗仮説 (要ログ確認)

`AudioKit/AudioEngine.swift:104-152` を確認: `engine.output = node` は `mainMixerNode` を作り `avEngine.connect(mixer, to: avEngine.outputNode)` で **ハードウェア出力ノードまで render chain を張る**。`start()` は `try avEngine.start()` (`:182`)。pitch engine はこれを **`.record` (出力 route 無し)** で実行。`.record` + 出力ノード接続は実機で `engine.start()` throw の既知要因。

無音出力は AudioKit の render を回して input tap を引くための定石だが、`.record` 下ではリスク。**対策候補**: (a) category を `.playAndRecord` (`mode: .measurement` 維持、出力は muted mixer のままで無音) にする、または (b) 出力を張らず input tap のみで駆動。どちらが正しいかは**追加済み診断ログの `stage=engine.start` 有無で確定**してから選ぶ。

---

## 6. 持続的マイク占有 (文言どおりの真因 / 審査落ち経路)

画面収録+マイク・ReplayKit ブロードキャスト・録音アプリ・通話が入力を保持中は `setActive(true)` が `IsBusy`/`CannotInterruptOthers (560557684)`/`InsufficientPriority (561015905)` を投げ続け、`.engineUnavailable` → 「ほかのアプリが使用中…もう一度」。占有が続く限り「もう一度」も失敗。App Store レビュー環境 (多重起動・収録中) で最も起きやすい拒否経路。

**対策**: (a) OSStatus を分類して文言を出し分け (占有 vs 入力無し)。(b) 失敗後に `routeChange`/interruption `.ended` を観測し、占有解放時に自動 retry。(c) `setActive(false)` に `.notifyOthersOnDeactivation` を付け、退出時に他アプリ音源を復帰させる。

---

## 7. 権限の再確認欠落

`retry()` (`TunerViewModel.swift:118-120`)、`.active` retry、`exitToneMode()` (`:142-158`、cached `permissionState` 使用) は `AVAudioApplication.shared.recordPermission` を再読しない。拒否状態でフォアグラウンド復帰 → `startEngine()` が無音 `.listening` で `.permissionDenied` を上書き (= 「設定を開く」導線が消える)。iOS は revoke 時に app を kill するため revoke 経路の到達性は低いが、**起動時拒否 → 復帰**経路は到達可能。

**対策**: `PitchEngine` に非プロンプトの `currentPermission` を公開し、`startEngine()`/`retry()`/`exitToneMode()`/`.active` retry の先頭で判定。`.denied`→`.permissionDenied`、`.undetermined`→再 `requestPermission()`、`.granted`→`engine.start()`。

---

## 8. Bluetooth HFP narrowband による検出劣化

`.allowBluetoothHFP` + `.measurement`: AirPods/BT 接続時に入力が 8/16kHz HFP mono に切替 → ピッチ検出が破綻し「壊れている」体感 (route 変更でも自動切替)。チューナーは内蔵マイクの広帯域入力が望ましい。

**対策**: `.allowBluetoothHFP` を外す、または `setPreferredInput` で built-in mic を優先。

---

## クリティックが指摘した追加の死角

| 重大度 | 死角 | 対策方向 |
|---|---|---|
| High | `AVAudioEngine.configurationChangeNotification` を未観測 — route 変更を伴わない I/O 構成変化で PitchTap が止まり誰も再起動しない | 同通知を購読し再起動 |
| Med | AirPods 接続済での A2DP→HFP 切替が **activation 中**に発生し初回 throw (#1 とは別系統) | activation を route settle 後に |
| Med | USB-C/Lightning オーディオ I/F (本アプリの中核ユーザ) が `.measurement` 入力になり multichannel/ch0空/sample-rate 不一致で無音 or throw | 入力フォーマット検証・チャネル選択 |
| Med | `UIBackgroundModes:audio` 無し → 非 active の隙間で `setActive(true)` が拒否され、握り潰し経路で消える | foreground gating + #2 の可視化 |
| Low | 熱制御 / 低電力モードが付与後 HAL settle 窓を広げ #1 のレースを悪化 | #1 のバックオフで吸収 |

---

## 推奨対応順 (独立 PR 単位)

1. **#4 `PitchEngine.onStopped/onError` 追加 + #2/#3 を UI へ可視化** (構造の要。これ単体で「無音の死んだマイク」群が解消)
2. **#1 初回付与後の bounded retry/backoff** (報告 repro 直撃)
3. **#5 category 確定** — 追加済みログで `engine.start` 失敗を確認してから `.playAndRecord` か output 撤去を選択
4. **#6 OSStatus 分類 + 解放時自動 retry + `.notifyOthersOnDeactivation`** (占有・審査経路 + 文言精度)
5. **#7 権限再確認** / **#8 入力選択** (堅牢化・品質)

> 注: 検証フェーズはレート制限で未完。本レポートの判定は人間 lens の突き合わせによる。実機の確定診断は追加済みログ (`subsystem:com.yutabee.tone category:PitchEngine`) を最優先で取得すること。
