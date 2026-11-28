# Drel 1.5.6 What's New

Status: release notes for 1.5.6 (build 161), prepared 2026-11-28.

1.5.6 is the first TestFlight build after 1.5.5 (build 160, in review). It
carries the "open untrusted apps as web pages" rework and the My Apps surface
rebuild from PR #31.

## zh-Hans

```text
Drel 1.5.6 更新

• 推送里"打开应用"不再卡死：应用未注册或无法验证时，自动改用网页方式打开，并提示可添加到"我的应用"
• 通知横幅打开应用失败时不再静默，会给出原因和"查看诊断"
• "我的应用"连接失败时显示真实原因，并提供重试和查看诊断；空状态新增"从推送添加"和"输入应用地址"
• 新增"输入应用地址"：粘贴网址或应用 ID 即可打开，验证通过的应用可直接加入"我的应用"
• 离线包下载失败按原因区分提示（网络中断 / 校验未通过 / 需要更新 Drel）
• 修复 57 处界面文案显示为原始键名的问题
• "添加到主屏幕"引导改为 drel:// 直链，修复无法拉起 Drel 的问题
```

## en-US

```text
Drel 1.5.6

• "Open app" from a push no longer dead-ends: when an app is unregistered or cannot be verified, Drel opens its site as a normal web page and offers to add it to My Apps
• A notification banner that fails to open its app now shows the reason and a diagnostics link instead of staying silent
• "My Apps" shows the real gateway failure with Retry and View Diagnostics; the empty state offers "add from a push" and "enter an app address"
• New "enter an app address": paste a URL or app id to open it; a verified app can be added to My Apps directly
• Offline package failures are reported by cause (network / checksum / needs a newer Drel)
• Fixed 57 interface strings that rendered as raw keys
• The "Add to Home Screen" guide now uses drel:// links, fixing hand-offs that could not open Drel
```

## ja

```text
Drel 1.5.6

• プッシュの「アプリを開く」が止まらなくなりました：未登録や検証できないアプリは Web ページとして開き、「マイアプリ」への追加を案内します
• 通知バナーからアプリを開けなかった場合、無音ではなく理由と診断リンクを表示します
• 「マイアプリ」は接続失敗の実際の理由を表示し、再試行と診断を提供します。空状態には「プッシュから追加」「アプリのアドレスを入力」があります
• 新機能「アプリのアドレスを入力」：URL またはアプリ ID を貼り付けて開きます。検証済みアプリはそのまま追加できます
• オフラインパッケージの失敗は原因別（ネットワーク／チェックサム／新しい Drel が必要）に表示されます
• 生のキー名として表示されていた 57 件の UI 文字列を修正しました
• 「ホーム画面に追加」ガイドを drel:// リンクに変更し、Drel を開けなかった問題を修正しました
```

## ko

```text
Drel 1.5.6

• 푸시에서 '앱 열기'가 더 이상 멈추지 않습니다: 미등록 또는 검증 불가 앱은 일반 웹 페이지로 열고 '내 앱' 추가를 안내합니다
• 알림 배너에서 앱을 열지 못하면 무음 대신 이유와 진단 링크를 표시합니다
• '내 앱'은 실제 게이트웨이 오류를 표시하고 재시도 및 진단을 제공합니다. 빈 상태에는 '푸시에서 추가'와 '앱 주소 입력'이 있습니다
• 새로운 '앱 주소 입력': URL 또는 앱 ID를 붙여넣어 열고, 검증된 앱은 바로 추가할 수 있습니다
• 오프라인 패키지 실패는 원인별(네트워크 / 체크섬 / 최신 Drel 필요)로 표시됩니다
• 원본 키로 표시되던 UI 문자열 57건을 수정했습니다
• '홈 화면에 추가' 안내를 drel:// 링크로 변경해 Drel을 열지 못하던 문제를 수정했습니다
```

## de-DE

```text
Drel 1.5.6

• „App öffnen“ aus einem Push läuft nicht mehr ins Leere: Ist eine App nicht registriert oder nicht verifizierbar, öffnet Drel ihre Website als normale Webseite und bietet an, sie zu „Meine Apps“ hinzuzufügen
• Ein Benachrichtigungsbanner, der seine App nicht öffnen kann, zeigt jetzt den Grund und einen Diagnose-Link, statt stumm zu bleiben
• „Meine Apps“ zeigt den tatsächlichen Gateway-Fehler mit „Erneut versuchen“ und „Diagnose anzeigen“; der Leerzustand bietet „Aus Push hinzufügen“ und „App-Adresse eingeben“
• Neu: „App-Adresse eingeben“ – URL oder App-ID einfügen zum Öffnen; eine verifizierte App kann direkt hinzugefügt werden
• Offline-Paket-Fehler werden nach Ursache gemeldet (Netzwerk / Prüfsumme / neueres Drel nötig)
• 57 UI-Texte korrigiert, die als Rohschlüssel angezeigt wurden
• Der „Zum Home-Bildschirm“-Leitfaden verwendet jetzt drel://-Links und behebt damit Übergaben, die Drel nicht öffnen konnten
```

## Submission notes

- No entitlement, Bridge action, permission surface or data collection changed
  in 1.5.6. The capability surface is identical to 1.5.5.
- The web fallback opens untrusted apps in the normal browser only: it never
  installs a manifest, never grants native capabilities and never installs an
  offline package. Derived addresses refuse loopback, link-local, RFC 1918,
  CGNAT, multicast, `.local`, IPv6 literals and URLs with userinfo.
- This build is for TestFlight. 1.5.5 (build 160) is still in App Review; a
  Store submission for 1.5.6 should wait until 1.5.5 is resolved.
