# Release Notes — kazahana for iOS v3.2.0

## EN

### New Features

- **Evacuation Assist** — A new opt-in feature that helps users find the nearest designated emergency evacuation shelter during weather emergencies. Based on JMA (Japan Meteorological Agency) hazard level information via bsaf-kikikuru-bot, it provides:
  - Alert banners (Level 3/4/5) with auto-detection via BSAF
  - Nearest shelter search with disaster type filtering (flood, landslide, earthquake, tsunami, etc.)
  - Compass-based offline navigation with real-time bearing and distance
  - Apple Maps delegation for turn-by-turn navigation
  - Bundled shelter data (115,447 GSI designated sites) for full offline capability
  - First-launch onboarding dialog explaining the feature
  - Disclaimer and data source attribution (GSI / JMA)

### Bug Fixes

- **Chat link visibility** — Links in the sender's own message bubbles (blue background) were invisible because link color matched the background. Links now display as white text with underline for readability.

### Documentation

- `README.md` / `README.ja.md` updated with Evacuation Assist feature

---

## JA

### 新機能

- **避難誘導補助** — 気象緊急時に最寄りの指定緊急避難場所を案内するオプトイン機能を追加しました。気象庁の危険度情報（bsaf-kikikuru-bot 経由）に基づき、以下の機能を提供します:
  - 警報バナー表示（レベル3/4/5）— BSAF による自動検知
  - 最寄り避難所検索 — 災害種別フィルタ対応（洪水・土砂災害・地震・津波等）
  - コンパス簡易ナビ — オフラインでも方位角・直線距離をリアルタイム更新
  - Apple Maps 委譲 — ターンバイターンナビゲーション
  - 避難所データ同梱（国土地理院 指定緊急避難場所 115,447件）— 完全オフライン動作
  - 初回起動時のオンボーディングダイアログ
  - 免責文言・出典表示（国土地理院・気象庁）

### バグ修正

- **チャットリンクの視認性改善** — 自分のメッセージ吹き出し（青背景）でリンク文字色が背景色と同じため判読できなかった問題を修正。リンクを白文字＋下線で表示するようにしました。

### ドキュメント

- `README.md` / `README.ja.md` — 避難誘導補助機能を追記
