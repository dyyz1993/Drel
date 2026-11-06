# Drel 1.5.3 What’s New

Status: owner-review draft for the 1.5.3 metadata-only release. The app
binary is unchanged; this version ships App Store listing work only. The
public copy below describes no app capability claims because the app surface
did not change; the review notes carry the full capability detail.

## zh-Hans

```text
Drel 1.5.3 更新

• 新增日语、韩语、德语商店页面与搜索关键词支持
• 英语商店描述经过润色，与简体中文描述内容保持一致
• 未覆盖语言的商店页面将回退到英语（此前为简体中文）
• 本次为商店信息更新，App 功能与 1.5.2 完全一致
```

## en-US

```text
Drel 1.5.3

• Added Japanese, Korean, and German App Store listings with localized search keywords
• Refined the English App Store description to match the Simplified Chinese listing
• Store pages in other markets now fall back to English instead of Simplified Chinese
• This release updates store information only; app functionality is identical to 1.5.2
```

## ja

```text
Drel 1.5.3

• 日本語・韓国語・ドイツ語のストアページと検索キーワードを追加
• 英語のストア説明を更新し、簡体字中国語の説明と内容を統一
• 未対応言語のストアページは簡体字中国語から英語へフォールバック
• 今回はストア情報の更新のみで、アプリ機能は 1.5.2 と同一です
```

## ko

```text
Drel 1.5.3

• 일본어, 한국어, 독일어 스토어 페이지와 검색 키워드 추가
• 영어 스토어 설명을 다듬어 간체 중국어 설명과 내용을 일치시켰습니다
• 지원하지 않는 언어의 스토어 페이지는 간체 중국어 대신 영어로 표시됩니다
• 이번 릴리스는 스토어 정보 업데이트만 포함하며, 앱 기능은 1.5.2와 동일합니다
```

## de-DE

```text
Drel 1.5.3

• Japanische, koreanische und deutsche Store-Seiten mit lokalisierten Suchbegriffen hinzugefügt
• Die englische Store-Beschreibung wurde an die chinesische Beschreibung angeglichen
• Store-Seiten in weiteren Märkten fallen jetzt auf Englisch statt Chinesisch zurück
• Dieses Update betrifft nur die Store-Informationen; die App entspricht Version 1.5.2
```

## Submission notes

- The app binary is unchanged; attach the same build train as 1.5.2 (a fresh
  upload is required because App Store Connect binds a build to one version).
- Switch the primary App Store locale to `en-US` in the same submission.
- App Store `whatsNew` per locale must use the localized blocks above.
