# kazahana-ios
> Kazahana iOS is a native Bluesky client for iOS, built with Swift and SwiftUI.

## Reference
- **モバイル仕様書**: `../kazahana/design/kazahana-mobile-spec.md`
- **デスクトップ版仕様書**: `../kazahana/design/kazahana-spec.md`
- **BSAF仕様**: `../bsaf-protocol/docs/bsaf-spec-ja.md`
- **多言語リソース元**: `../kazahana/src/i18n/locales/*.json`

## Task Management
- **task_file**: `Documentation/tasks.md`
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

## Cross-Platform Management

- **platform_matrix**: `https://github.com/osprey74/kazahana/blob/main/docs/PLATFORM_MATRIX.md`
  - 全プラットフォームの機能実装状況を管理する唯一の正本（kazahana リポジトリに格納）
  - 機能追加・修正完了時は **必ずこのファイルの該当セルを更新**すること
- **issue_hub**: `https://github.com/osprey74/kazahana/issues`
  - iOS 固有の作業も含め、すべての Issue を kazahana リポジトリで一元管理
  - Issue 作成時は `platform:ios` ラベルを付与すること
- **matrix_update_rule**:
  1. 機能実装完了 → platform_matrix の iOS 列の該当セルを `✅` に変更
  2. 未実装を発見 → `⬜` に変更し、kazahana Issues に `parity` + `platform:ios` ラベルで Issue を作成
  3. `❓` を解消 → ソース確認後に `✅` か `⬜` に変更
  4. 変更は kazahana リポジトリの `docs/matrix-update-YYYYMMDD` ブランチで PR を出す
- **issue_labels**:
  - `platform:ios`  — このリポジトリの作業に付与
  - `parity`        — Desktop / Android との差異是正タスク
  - `matrix:update` — PLATFORM_MATRIX.md の更新が必要

## SNS
- **sns_accounts**:
  - Bluesky: `@app-kazahana.bsky.social`
