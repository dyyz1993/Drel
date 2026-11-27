# Drel 1.5.5 What's New

Status: release notes for 1.5.5 (build 160), prepared 2026-11-27.

App Store Connect approved 1.5.4 as build 143, but that build predates most
of the fixes recorded under 1.5.4, and it was never released. 1.5.5 is built
from the current `main`, so these notes describe everything a user on 1.5.3
receives: the nine items of the 1.5.4 notes plus the offline cold-start change
that landed with build 156.

## zh-Hans

```text
Drel 1.5.5 更新

• 新增"时效性通知"能力：标记为"紧急"的推送可穿透专注模式和静音开关
• 修复 Voice 演示所需的实时音量能力
• 修复推送打开应用时重复跳转，且第二层页面丢失全屏样式的问题
• 进一步修复部分启动路径下推送仍触发二次普通页面的问题
• 离线包本机入口加载失败时自动回退到联网入口
• 下载离线包时展示总体积和进度
• 新增"离线应用诊断"面板：本机记录最近打开的阶段，便于排查离线包问题
• 修复延迟渲染的离线页面被误判失败而误切在线兜底的问题
• 离线包按钮仅在有新版本时显示"更新"，同版本、回退或无法比较的版本一律显示"重新下载"
• 离线冷启动时，本地离线包只要通过完整性校验就直接打开，不再因版本较旧而失败
```

## en-US

```text
Drel 1.5.5

• Added Time Sensitive Notifications: pushes marked as urgent can now break through Focus mode and the silent switch
• Restored the real-time audio-level capability used by the Voice demos
• Fixed duplicate navigation after opening an app push and the second page losing immersive presentation
• Further fixed a lifecycle path where a push could still trigger a second normal page
• Added automatic online fallback when a strong-offline package entrypoint fails to load
• Offline package downloads now show total size and progress
• Added an offline app diagnostics panel with local per-launch stage records
• Fixed late-rendering offline pages being misjudged and unnecessarily switched online
• The offline package button offers "Update" only for strictly newer remote versions; same-version, downgraded, or uncomparable versions show "Redownload"
• On an offline cold start, an installed offline package now opens as soon as it passes integrity verification, even when a newer version exists
```

## ja

```text
Drel 1.5.5

• 時刻対応通知機能を追加：「緊急」マーク付きプッシュは集中モードとサイレントスイッチを貫通します
• Voiceデモが使うリアルタイム音量機能を復旧しました
• アプリプッシュ起動時の二重遷移と、2番目のページで没入型表示が失われる問題を修正しました
• 一部の起動経路でプッシュ後に通常ページが再び開く問題をさらに修正しました
• 強力オフラインパッケージの読み込みに失敗した場合、オンラインページへ自動的に切り替えます
• オフラインパッケージのダウンロード時に合計サイズと進捗を表示します
• オフラインアプリ診断パネルを追加：端末内に起動段階を記録し調査しやすくしました
• 遅延描画されるオフラインページの誤判定と不要なオンライン切替を修正しました
• オフラインパッケージのボタンは、リモートバージョンが確実に新しい場合のみ「更新」と表示し、同版本・ダウングレード・比較不能な場合は「再ダウンロード」と表示します
• オフラインでのコールド起動時、インストール済みのオフラインパッケージは完全性検証を通れば、新しいバージョンがあってもそのまま起動します
```

## ko

```text
Drel 1.5.5

• 시간 민감 알림 기능 추가: '긴급' 표시된 푸시는 방해 금지 모드와 무음 스위치를 관통합니다
• Voice 데모에 필요한 실시간 오디오 레벨 기능을 복원했습니다
• 앱 푸시 실행 시 이중 전환과 두 번째 페이지의 전체 화면 표시 손실 문제를 수정했습니다
• 일부 실행 경로에서 푸시 후 일반 페이지가 다시 열리는 문제를 추가로 수정했습니다
• 강력 오프라인 패키지 로드에 실패하면 온라인 페이지로 자동 전환합니다
• 오프라인 패키지 다운로드 시 전체 크기와 진행률이 표시됩니다
• 오프라인 앱 진단 패널 추가: 기기 내 실행 단계를 기록해 문제 파악이 쉬워졌습니다
• 늦게 렌더링되는 오프라인 페이지의 오판과 불필요한 온라인 전환을 수정했습니다
• 오프라인 패키지 버튼은 원격 버전이 확실히 새로운 경우에만 '업데이트'로 표시되고, 동일 버전·다운그레이드·비교 불가 버전은 '다시 다운로드'로 표시됩니다
• 오프라인 콜드 스타트 시 설치된 오프라인 패키지가 무결성 검증을 통과하면 최신 버전이 있어도 바로 열립니다
```

## de-DE

```text
Drel 1.5.5

• Zeitkritische Benachrichtigungen hinzugefügt: Als "dringend" markierte Push-Benachrichtigungen durchbrechen jetzt den Fokusmodus und den Stummschalter
• Die von den Voice-Demos genutzte Echtzeit-Pegel-Funktion wurde wiederhergestellt
• Doppelte Navigation beim Öffnen eines App-Push behoben und den Verlust der immersiven Darstellung auf der zweiten Seite korrigiert
• Ein Lifecycle-Pfad wurde zusätzlich korrigiert, bei dem nach einem Push eine zweite normale Seite geöffnet werden konnte
• Wenn das Laden eines Offline-Pakets fehlschlägt, wird automatisch zur Online-Seite gewechselt
• Offline-Paket-Downloads zeigen jetzt Gesamtgröße und Fortschritt
• Offline-App-Diagnose-Panel hinzugefügt: lokale Aufzeichnung der Startphasen
• Fehlbeurteilung spät gerenderter Offline-Seiten und unnötige Online-Umschaltung behoben
• Der Offline-Paket-Button bietet "Update" nur bei strikt neueren Remote-Versionen; gleiche, ältere oder nicht vergleichbare Versionen zeigen "Erneut laden"
• Beim Offline-Kaltstart öffnet ein installiertes Offline-Paket jetzt direkt, sobald es die Integritätsprüfung besteht, auch wenn eine neuere Version existiert
```

## Submission notes

- The binary carries one new entitlement:
  `com.apple.developer.usernotifications.time-sensitive`.
- The push payload already sets `interruption-level: time-sensitive` when the
  sender uses `level=timeSensitive`; this entitlement makes iOS honor it.
- `Drel15Release` re-enables `DREL_151_MICROPHONE`, so the 9-action allowlist
  — including the revocable `audioLevel` action described in the 1.5.3 review
  notes — matches the shipped binary again.
- Builds 146-153 fixed cold-launch navigation after a push, added the
  strong-offline online fallback, kept the downloaded resource manifest for
  integrity checks, made `drel_offline.version` optional, and added verified
  package-size display. See the 1.5.4 release notes for the per-build list.
- Build 154 added the offline app diagnostics panel; build 155 made the
  offline package update action appear only for strictly newer versions.
- Build 156 launches an installed offline package on a confirmed offline cold
  start when it passes integrity verification, even if a newer version exists.
- Build 160 is built from `main` at this release. Compared with build 159, the
  app sources differ only in a demo-data placeholder string; the version is
  1.5.5.
