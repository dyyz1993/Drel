# Drel 1.5.4 What's New

Status: owner-review draft for the 1.5.4 release. The functional changes are
the `com.apple.developer.usernotifications.time-sensitive` entitlement (so
`level=time-sensitive` pushes break through Focus mode and the silent switch)
and restoring the audioLevel Bridge action that builds 141–143 accidentally
dropped from the `Drel15Release` compile conditions.

## zh-Hans

```text
Drel 1.5.4 更新

• 新增"时效性通知"能力：标记为"紧急"的推送可穿透专注模式和静音开关
• 修复 Voice 演示所需的实时音量能力
• 修复推送打开应用时重复跳转，且第二层页面丢失全屏样式的问题
• 进一步修复部分启动路径下推送仍触发二次普通页面的问题
• 离线包本机入口加载失败时自动回退到联网入口
• 下载离线包时展示总体积和进度
• 新增"离线应用诊断"面板：本机记录最近打开的阶段，便于排查离线包问题
• 修复延迟渲染的离线页面被误判失败而误切在线兜底的问题
• 离线包按钮仅在有新版本时显示"更新"，同版本、回退或无法比较的版本一律显示"重新下载"
```

## en-US

```text
Drel 1.5.4

• Added Time Sensitive Notifications: pushes marked as urgent can now break through Focus mode and the silent switch
• Restored the real-time audio-level capability used by the Voice demos
• Fixed duplicate navigation after opening an app push and the second page losing immersive presentation
• Further fixed a lifecycle path where a push could still trigger a second normal page
• Added automatic online fallback when a strong-offline package entrypoint fails to load
• Offline package downloads now show total size and progress
• Added an offline app diagnostics panel with local per-launch stage records
• Fixed late-rendering offline pages being misjudged and unnecessarily switched online
• The offline package button offers "Update" only for strictly newer remote versions; same-version, downgraded, or uncomparable versions show "Redownload"
```

## ja

```text
Drel 1.5.4

• 時刻対応通知機能を追加：「緊急」マーク付きプッシュは集中モードとサイレントスイッチを貫通
• Voiceデモが使うリアルタイム音量機能を復旧しました
• アプリプッシュ起動時の二重遷移と、2番目のページで没入型表示が失われる問題を修正しました
• 一部の起動経路でプッシュ後に通常ページが再び開く問題をさらに修正しました
• 強力オフラインパッケージの読み込みに失敗した場合、オンラインページへ自動的に切り替えます
• オフラインパッケージのダウンロード時に合計サイズと進捗を表示します
• オフラインアプリ診断パネルを追加：端末内に起動段階を記録し調査しやすくしました
• 遅延描画されるオフラインページの誤判定と不要なオンライン切替を修正しました
• オフラインパッケージのボタンは、リモートバージョンが確実に新しい場合のみ「更新」と表示し、同版本・ダウングレード・比較不能な場合は「再ダウンロード」と表示します
```

## ko

```text
Drel 1.5.4

• 시간 민감 알림 기능 추가: '긴급' 표시된 푸시는 방해 금지 모드와 무음 스위치를 관통합니다
• Voice 데모에 필요한 실시간 오디오 레벨 기능을 복원했습니다
• 앱 푸시 실행 시 이중 전환과 두 번째 페이지의 전체 화면 표시 손실 문제를 수정했습니다
• 일부 실행 경로에서 푸시 후 일반 페이지가 다시 열리는 문제를 추가로 수정했습니다
• 강력 오프라인 패키지 로드에 실패하면 온라인 페이지로 자동 전환합니다
• 오프라인 패키지 다운로드 시 전체 크기와 진행률이 표시됩니다
• 오프라인 앱 진단 패널 추가: 기기 내 실행 단계를 기록해 문제 파악이 쉬워졌습니다
• 늦게 렌더링되는 오프라인 페이지의 오판과 불필요한 온라인 전환을 수정했습니다
• 오프라인 패키지 버튼은 원격 버전이 확실히 새로운 경우에만 '업데이트'로 표시되고, 동일 버전·다운그레이드·비교 불가 버전은 '다시 다운로드'로 표시됩니다
```

## de-DE

```text
Drel 1.5.4

• Zeitkritische Benachrichtigungen hinzugefügt: Als "dringend" markierte Push-Benachrichtigungen durchbrechen jetzt den Fokusmodus und den Stummschalter
• Die von den Voice-Demos genutzte Echtzeit-Pegel-Funktion wurde wiederhergestellt
• Doppelte Navigation beim Öffnen eines App-Push behoben und den Verlust der immersiven Darstellung auf der zweiten Seite korrigiert
• Ein Lifecycle-Pfad wurde zusätzlich korrigiert, bei dem nach einem Push eine zweite normale Seite geöffnet werden konnte
• Wenn das Laden eines Offline-Pakets fehlschlägt, wird automatisch zur Online-Seite gewechselt
• Offline-Paket-Downloads zeigen jetzt Gesamtgröße und Fortschritt
• Offline-App-Diagnose-Panel hinzugefügt: lokale Aufzeichnung der Startphasen
• Fehlbeurteilung spät gerenderter Offline-Seiten und unnötige Online-Umschaltung behoben
• Der Offline-Paket-Button bietet "Update" nur bei strikt neueren Remote-Versionen; gleiche, ältere oder nicht vergleichbare Versionen zeigen "Erneut laden"
```

## Submission notes

- The binary carries one new entitlement:
  `com.apple.developer.usernotifications.time-sensitive`.
- The push payload already sets `interruption-level: time-sensitive` when the
  sender uses `level=timeSensitive`; this entitlement makes iOS honor it.
- `Drel15Release` re-enables `DREL_151_MICROPHONE`, so the 9-action allowlist
  — including the revocable `audioLevel` action described in the 1.5.3 review
  notes — matches the shipped binary again.
- Build 146 fixes duplicate cold-launch navigation from a push and preserves
  the immersive presentation for the explicit notification destination.
- Build 147 additionally marks notification and external app launches as
  explicit destinations in the notification delegate path; this closes the
  lifecycle case where Scene connection metadata omitted the notification
  response and recent-session restore still ran.
- Build 148 adds a bounded fallback from a failed strong-offline package
  entrypoint to the trusted online start URL.
- Build 149 preserves the downloaded resource manifest separately from
  installer metadata, validates package integrity on cold launch, waits briefly
  for Gateway manifests during default startup, and no longer restores stale
  absolute `file://` sessions.
- Build 150 extends the strong-offline online fallback to immersive browser
  pages, covering delete/reinstall flows where the restored local entrypoint
  fails but the signed HTTPS shell is available.
- Build 151 makes the duplicated `drel_offline.version` field optional. New
  PWA-first manifests inherit the version from the signed parent cache while
  older manifests remain installable.
- Build 152 fixes the Store immersive-browser path: the trusted HTTPS page is
  retained separately from the local document, so a failed offline package
  navigation can recover online even when the native bridge is disabled.
- Build 153 adds verified package-size display and cumulative byte progress
  while strong-offline resources download.
- Build 155 compares offline package versions numerically and offers the
  update action only for strictly newer remote packages; same-version,
  downgraded, or uncomparable versions offer a redownload instead.
