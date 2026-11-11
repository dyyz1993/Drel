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
• 修复近期构建缺少实时音量能力导致 Voice 演示不可用的问题
```

## en-US

```text
Drel 1.5.4

• Added Time Sensitive Notifications: pushes marked as urgent can now break through Focus mode and the silent switch
• Restored the real-time audio-level capability used by the Voice demos, which was missing from builds 141–143
```

## ja

```text
Drel 1.5.4

• 時刻対応通知機能を追加：「緊急」マーク付きプッシュは集中モードとサイレントスイッチを貫通
• Voiceデモが使うリアルタイム音量機能を復旧しました（ビルド141〜143で欠落）
```

## ko

```text
Drel 1.5.4

• 시간 민감 알림 기능 추가: '긴급' 표시된 푸시는 방해 금지 모드와 무음 스위치를 관통합니다
• Voice 데모에 필요한 실시간 오디오 레벨 기능을 복원했습니다 (빌드 141–143에서 누락)
```

## de-DE

```text
Drel 1.5.4

• Zeitkritische Benachrichtigungen hinzugefügt: Als "dringend" markierte Push-Benachrichtigungen durchbrechen jetzt den Fokusmodus und den Stummschalter
• Die von den Voice-Demos genutzte Echtzeit-Pegel-Funktion wurde wiederhergestellt (fehlte in Builds 141–143)
```

## Submission notes

- The binary carries one new entitlement:
  `com.apple.developer.usernotifications.time-sensitive`.
- The push payload already sets `interruption-level: time-sensitive` when the
  sender uses `level=timeSensitive`; this entitlement makes iOS honor it.
- `Drel15Release` re-enables `DREL_151_MICROPHONE`, so the 9-action allowlist
  — including the revocable `audioLevel` action described in the 1.5.3 review
  notes — matches the shipped binary again.
