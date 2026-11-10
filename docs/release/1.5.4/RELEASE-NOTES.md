# Drel 1.5.4 What's New

Status: owner-review draft for the 1.5.4 release. The only functional change
is the addition of the `com.apple.developer.usernotifications.time-sensitive`
entitlement. This allows notifications sent with `level=time-sensitive` to
break through Focus mode and the silent switch, matching Bark's behavior.

## zh-Hans

```text
Drel 1.5.4 更新

• 新增"时效性通知"能力：标记为"紧急"的推送可穿透专注模式和静音开关
• 其他功能与 1.5.3 完全一致
```

## en-US

```text
Drel 1.5.4

• Added Time Sensitive Notifications: pushes marked as urgent can now break through Focus mode and the silent switch
• Other functionality is identical to 1.5.3
```

## ja

```text
Drel 1.5.4

• 時刻対応通知機能を追加：「緊急」マーク付きプッシュは集中モードとサイレントスイッチを貫通
• その他の機能は 1.5.3 と同一です
```

## ko

```text
Drel 1.5.4

• 시간 민감 알림 기능 추가: '긴급' 표시된 푸시는 방해 금지 모드와 무음 스위치를 관통합니다
• 기타 기능은 1.5.3과 동일합니다
```

## de-DE

```text
Drel 1.5.4

• Zeitkritische Benachrichtigungen hinzugefügt: Als "dringend" markierte Push-Benachrichtigungen durchbrechen jetzt den Fokusmodus und den Stummschalter
• Andere Funktionen sind identisch mit 1.5.3
```

## Submission notes

- The binary carries one new entitlement:
  `com.apple.developer.usernotifications.time-sensitive`.
- The push payload already sets `interruption-level: time-sensitive` when the
  sender uses `level=timeSensitive`; this entitlement makes iOS honor it.
- No Bridge action or permission surface changes; the same 9-action allowlist
  applies. Review notes from 1.5.3 carry forward unchanged.
