# kazahana-ios

> Kazahana iOS is a native Bluesky client for iOS, built with Swift and SwiftUI.

## Reference

- **モバイル仕様書**: `../kazahana/design/kazahana-mobile-spec.md`
- **デスクトップ版仕様書**: `../kazahana/design/kazahana-spec.md`
- **BSAF仕様**: `../bsaf-protocol/docs/bsaf-spec-ja.md`
- **多言語リソース元**: `../kazahana/src/i18n/locales/*.json`

## Task Management

- **task_file**: `docs/tasks.md`
- **done_marker**: `[x]`
- **progress_summary**: true

## Documentation

- **docs_to_update**:
  - `README.md` (EN)
  - `README.ja.md` (JA)
- **doc_pairs**:
  - `README.md` ↔ `README.ja.md`

## Versioning

- **version_files**:
  - Xcode project (MARKETING_VERSION / CURRENT_PROJECT_VERSION)

## CI/CD

- **cicd**: false
- **cicd_note**: 将来的に GitHub Actions (macOS runner) or Xcode Cloud を導入予定

## SNS

- **sns_accounts**:
  - Bluesky: `@app-kazahana.bsky.social`
