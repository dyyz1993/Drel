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
```

## en-US

```text
Drel 1.5.4

• Added Time Sensitive Notifications: pushes marked as urgent can now break through Focus mode and the silent switch
• Restored the real-time audio-level capability used by the Voice demos
• Fixed duplicate navigation after opening an app push and the second page losing immersive presentation
• Further fixed a lifecycle path where a push could still trigger a second normal page
```

## ja

```text
Drel 1.5.4

• 時刻対応通知機能を追加：「緊急」マーク付きプッシュは集中モードとサイレントスイッチを貫通
• Voiceデモが使うリアルタイム音量機能を復旧しました
• アプリプッシュ起動時の二重遷移と、2番目のページで没入型表示が失われる問題を修正しました
• 一部の起動経路でプッシュ後に通常ページが再び開く問題をさらに修正しました
```

## ko

```text
Drel 1.5.4

• 시간 민감 알림 기능 추가: '긴급' 표시된 푸시는 방해 금지 모드와 무음 스위치를 관통합니다
• Voice 데모에 필요한 실시간 오디오 레벨 기능을 복원했습니다
• 앱 푸시 실행 시 이중 전환과 두 번째 페이지의 전체 화면 표시 손실 문제를 수정했습니다
• 일부 실행 경로에서 푸시 후 일반 페이지가 다시 열리는 문제를 추가로 수정했습니다
```

## de-DE

```text
Drel 1.5.4

• Zeitkritische Benachrichtigungen hinzugefügt: Als "dringend" markierte Push-Benachrichtigungen durchbrechen jetzt den Fokusmodus und den Stummschalter
• Die von den Voice-Demos genutzte Echtzeit-Pegel-Funktion wurde wiederhergestellt
• Doppelte Navigation beim Öffnen eines App-Push behoben und den Verlust der immersiven Darstellung auf der zweiten Seite korrigiert
• Ein Lifecycle-Pfad wurde zusätzlich korrigiert, bei dem nach einem Push eine zweite normale Seite geöffnet werden konnte
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
