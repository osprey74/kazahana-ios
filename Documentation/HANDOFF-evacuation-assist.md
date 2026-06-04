# HANDOFF: 避難誘導補助機能（お節介避難ナビ）— kazahana-ios ネイティブ実装

| 項目 | 内容 |
|:--|:--|
| 機能名（仮） | 避難誘導補助機能 / Evacuation Assist |
| 対象アプリ | kazahana-ios（Swift / SwiftUI ネイティブ） |
| 元設計書 | `../kazahana/DESIGN_evacuation-assist.md` |
| ステータス | COMPLETED（iOS v3.2.0 でリリース済み） |
| 作成日 | 2026-06-03 |
| 完了日 | 2026-06-04 |
| 想定実装環境 | Claude Code |

> 本書は DESIGN_evacuation-assist.md を **kazahana-ios（ネイティブ Swift / SwiftUI）** 向けに再構成した実装指示書です。元 HANDOFF は Tauri v2 + React + TypeScript を前提としていたため、iOS ネイティブの技術スタックに全面的に読み替えています。

> **iOS 実装ステータス**: 全 5 フェーズ完了。v3.2.0 (build 17) で App Store 審査提出済み。

---

## 0. 前提と全体方針

### 0.1 設計思想（実装中も常に意識すること）

- **主体は人間、アプリは一助**。避難判断を代行する実装を入れないこと。自動避難判定・強制遷移は禁止。
- **お節介機能**。設定でオン／オフ可能な任意機能。デフォルトはオフとし、初回起動時に案内のみ行う。
- **先回り型の動線**。レベル3でバナー常駐、レベル4で動線が既に整っている状態を作る。即時プッシュには初期段階で依存しない。
- **オフライン耐性が最優先要件**。避難所データは端末同梱。通信途絶でもコンパス簡易ナビが動くこと。

### 0.2 扱う情報の性質（UI・文言で絶対に取り違えないこと）

- 本機能が扱うのは **気象庁の警報級・危険度情報（キキクル相当 / bsaf-kikikuru-bot）** であり、**自治体の避難指示そのものではない**。
- 文言で「避難指示が出ました」等の断定表現を使わないこと。「警報級の気象情報」「危険度情報」と表現する。

### 0.3 技術スタック（Tauri → iOS ネイティブ読み替え）

| 元設計（Tauri） | iOS ネイティブ |
|:--|:--|
| Tauri v2 Geolocation Plugin | **CoreLocation**（`CLLocationManager`） |
| GeoJSON / SQLite | **Bundle JSON**（`shelters.json` をアプリに同梱） |
| Haversine（Rust or TS） | **Swift 実装**（`CLLocation.distance(from:)` も併用可） |
| デバイスコンパス（磁気センサ） | **CoreLocation**（`CLHeading` / `startUpdatingHeading()`） |
| OS地図 URI スキーム | **MapKit**（`MKMapItem.openInMaps()`） |
| React コンポーネント | **SwiftUI View** |
| TypeScript モデル | **Swift struct**（`Codable`） |
| localStorage / Tauri store | **UserDefaults**（`AppSettings` 既存パターン） |

### 0.4 コードベースの規約（既存パターンに準拠）

- **アーキテクチャ**: MVVM + Services。ViewModel は `@Observable`、Services は struct / class。
- **永続化**: `AppSettings`（UserDefaults App Group `group.com.osprey74.kazahana`）。
- **ローカライズ**: `String(localized: "key")` + `Localizable.xcstrings`。キーは `evacuation.xxx` プレフィックス。
- **エラー型**: `LocalizedError` 準拠の enum。
- **依存注入**: `@Environment(AppSettings.self)` / init 経由。
- **非同期**: `async` / `await` + `@MainActor`。
- **デプロイターゲット**: iOS 18.0+。
- **外部依存**: なし（SPM パッケージ不使用。CoreLocation / MapKit はシステムフレームワーク）。

### 0.5 リポジトリ構成上の注意

- kazahana は Desktop / iOS / Android の3リポジトリ構成で、PLATFORM_MATRIX.md が SSOT。本機能はモバイル限定のため、PLATFORM_MATRIX.md に「Desktop: 非対象 / iOS: 対象 / Android: 対象」を追記すること。
- 本機能の Issue・ラベルは kazahana リポジトリに `platform:ios` で登録する。

### 0.6 bsaf-kikikuru-bot 登録前提

本機能は **bsaf-kikikuru-bot が BSAF ボットとして登録されていること** を前提とする。

- 避難誘導のトリガーとなる気象警報情報は bsaf-kikikuru-bot の投稿から取得する。
- 既存の BSAF パイプライン（`BsafService.parseBsafTags()` → `TimelineViewModel` での処理）をそのまま活用する。
- ボットがタイムラインに流れるには「BSAF 登録」と「Bluesky フォロー」の両方が必要だが、既存の `BsafBotsView` の登録フローで自動フォローが行われるため、BSAF 登録だけで足りる。
- 避難誘導機能をオンにする際、bsaf-kikikuru-bot が未登録であれば **確認メッセージを表示した上で自動的に BSAF 登録** する（Phase 1 の設定トグル参照）。

**bsaf-kikikuru-bot 定義 URL**（アプリにハードコード）:

```swift
/// bsaf-kikikuru-bot の BSAF Bot Definition JSON URL
static let kikikuruBotDefinitionUrl = "https://raw.githubusercontent.com/osprey74/bsaf-kikikuru-bot/main/bsaf-bot.json"
```

---

## 1. データモデル定義

### 1.1 避難所データ（同梱）

国土地理院 CSV から変換した JSON。`kazahana-ios/Resources/shelters.zlib（zlib 圧縮 JSON）` としてバンドル。

```swift
// Models/Shelter.swift

struct Shelter: Codable, Identifiable {
    let id: String              // 共通ID（国土地理院）
    let name: String            // 施設・場所名
    let lat: Double             // 緯度
    let lng: Double             // 経度
    let prefecture: String      // 都道府県（jp-xxxx 形式）
    let hazards: ShelterHazards // 対応災害種別フラグ
}

struct ShelterHazards: Codable {
    let flood: Bool             // 洪水
    let landslide: Bool         // 崖崩れ・土石流・地滑り
    let stormSurge: Bool        // 高潮
    let earthquake: Bool        // 地震
    let tsunami: Bool           // 津波
    let fire: Bool              // 大規模な火事
    let inlandFlood: Bool       // 内水氾濫
    let volcano: Bool           // 火山現象
}
```

### 1.2 警報状態（バナー制御用）

```swift
// Models/EvacuationAlert.swift

enum AlertLevel: String, Codable, Comparable {
    case level3 = "level3"
    case level4 = "level4"
    case level5 = "level5"

    // Comparable: level3 < level4 < level5
    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        let order: [AlertLevel] = [.level3, .level4, .level5]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

struct ActiveAlert: Codable, Identifiable, Equatable {
    let type: String            // BSAF type（heavy-rain-warning など）
    let value: AlertLevel       // BSAF value
    let time: String            // BSAF time（ISO8601, dedupe key の一部）
    let target: String          // BSAF target（jp-xxxx）
    let receivedAt: Date        // 受信時刻（タイムアウト判定用）

    var id: String { "\(type)|\(value.rawValue)|\(time)|\(target)" }
}
```

### 1.3 設定（AppSettings に追加）

```swift
// AppSettings.swift に追加するプロパティ

// MARK: - 避難誘導機能設定

/// 避難誘導機能の有効/無効（デフォルト false）
var evacuationEnabled: Bool {
    didSet { defaults.set(evacuationEnabled, forKey: "evacuationEnabled") }
}

/// 手動設定した都道府県（nil = 測位で判定）
var evacuationPrefectureOverride: String? {
    didSet {
        defaults.set(evacuationPrefectureOverride, forKey: "evacuationPrefectureOverride")
    }
}

/// 初回案内を表示済みか
var evacuationOnboardingShown: Bool {
    didSet { defaults.set(evacuationOnboardingShown, forKey: "evacuationOnboardingShown") }
}
```

`init()` で読み出し:

```swift
self.evacuationEnabled = d.object(forKey: "evacuationEnabled") as? Bool ?? false
self.evacuationPrefectureOverride = d.string(forKey: "evacuationPrefectureOverride")
self.evacuationOnboardingShown = d.object(forKey: "evacuationOnboardingShown") as? Bool ?? false
```

### 1.4 都道府県コード定義

BSAF `target` と突き合わせるための `jp-xxxx` 形式の都道府県マッピング。

```swift
// Models/Prefecture.swift

enum Prefecture: String, CaseIterable, Codable {
    case hokkaido = "jp-hokkaido"
    case aomori = "jp-aomori"
    case iwate = "jp-iwate"
    // ... 47都道府県すべて定義 ...
    case okinawa = "jp-okinawa"

    /// 表示名（設定画面用）
    var displayName: String {
        switch self {
        case .hokkaido: return "北海道"
        case .aomori: return "青森県"
        // ...
        case .okinawa: return "沖縄県"
        }
    }
}
```

---

## 2. Phase 1: 避難所データ変換・同梱 + 設定トグル

### 2.1 タスク

1. **データ変換スクリプト作成**（`scripts/build-shelters.py` or `scripts/build-shelters.swift`）
   - 国土地理院 CSV（全国版）を入力。
   - 1.1 の `Shelter` 形式の JSON 配列として出力。
   - 都道府県名を `jp-xxxx` 形式に正規化（BSAF の target と突き合わせるため）。
   - 災害種別フラグを確実にマッピング（CSV の各列 → Bool）。
   - 出力先: `kazahana-ios/Resources/shelters.json`
   - 出力サイズを確認（数MB目安）。

2. **ShelterService 作成**（`Services/ShelterService.swift`）
   - Bundle から `shelters.json` を読み込み `[Shelter]` にデコード。
   - 起動時に一度読み込んでメモリにキャッシュ（`static` プロパティ or ViewModel 経由）。
   - オフライン読み込みを保証（ネットワーク不要）。

```swift
// Services/ShelterService.swift

struct ShelterService {

    /// Bundle 同梱の避難所データを読み込む
    static func loadShelters() -> [Shelter] {
        guard let url = Bundle.main.url(forResource: "shelters", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let shelters = try? JSONDecoder().decode([Shelter].self, from: data)
        else { return [] }
        return shelters
    }

    /// Haversine 距離で最近傍の避難所を探索
    /// - hazardFilters: 災害種別フィルタ（OR 条件。いずれかに対応する施設を候補化。必須）
    /// - limit: 返却件数上限
    ///
    /// 大雨警報なら [\.flood, \.landslide, \.inlandFlood] のように複数指定する。
    /// 1つでも true なら候補に含める（OR 条件）。
    static func findNearest(
        shelters: [Shelter],
        from location: CLLocationCoordinate2D,
        hazardFilters: [KeyPath<ShelterHazards, Bool>],
        limit: Int = 5
    ) -> [ShelterWithDistance] {
        shelters
            .filter { shelter in
                hazardFilters.contains { shelter.hazards[keyPath: $0] }
            }
            .map { shelter in
                let distance = haversineDistance(
                    lat1: location.latitude, lng1: location.longitude,
                    lat2: shelter.lat, lng2: shelter.lng
                )
                return ShelterWithDistance(shelter: shelter, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    /// Haversine 距離計算（メートル）
    static func haversineDistance(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let R = 6_371_000.0 // 地球半径（m）
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}

struct ShelterWithDistance: Identifiable {
    let shelter: Shelter
    let distance: Double  // メートル

    var id: String { shelter.id }
}
```

3. **設定トグル + bsaf-kikikuru-bot 自動登録**（`AppSettings` + `SettingsView`）
   - `SettingsView.swift` の BSAF セクションの下に「避難誘導」セクションを追加。
   - トグルをオンにする際、bsaf-kikikuru-bot が未登録であれば **確認ダイアログを表示** し、承認後に自動登録する。
   - オンの場合のみ、都道府県手動設定 Picker を表示。

```swift
// SettingsView.swift に追加するセクション

@State private var showEvacuationBotConfirm = false
@State private var evacuationBotRegistering = false
@State private var evacuationBotError: String? = nil

// MARK: - 避難誘導機能
Section {
    Toggle(String(localized: "evacuation.enable"), isOn: Binding(
        get: { settings.evacuationEnabled },
        set: { newValue in
            if newValue {
                // bsaf-kikikuru-bot が未登録なら確認ダイアログ
                let kikikuruDid = "did:plc:..." // bsaf-kikikuru-bot の DID
                if settings.findRegisteredBot(did: kikikuruDid) == nil {
                    showEvacuationBotConfirm = true
                } else {
                    settings.evacuationEnabled = true
                    settings.bsafEnabled = true // BSAF も有効化
                }
            } else {
                settings.evacuationEnabled = false
            }
        }
    ))

    if settings.evacuationEnabled {
        Picker(String(localized: "evacuation.prefectureOverride"), selection: /* ... */) {
            Text(String(localized: "evacuation.prefectureAuto")).tag(nil as String?)
            ForEach(Prefecture.allCases, id: \.self) { pref in
                Text(pref.displayName).tag(pref.rawValue as String?)
            }
        }
    }

    if let error = evacuationBotError {
        Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
    }
} header: {
    Text(String(localized: "evacuation.title"))
} footer: {
    Text(String(localized: "evacuation.footer"))
}
.alert(String(localized: "evacuation.botConfirm.title"), isPresented: $showEvacuationBotConfirm) {
    Button(String(localized: "evacuation.botConfirm.enable")) {
        Task { await registerKikikuruBotAndEnable() }
    }
    Button(String(localized: "common.cancel"), role: .cancel) {}
} message: {
    Text(String(localized: "evacuation.botConfirm.message"))
}
```

自動登録の処理:

```swift
private func registerKikikuruBotAndEnable() async {
    evacuationBotRegistering = true
    evacuationBotError = nil
    do {
        let definition = try await BsafService.fetchBotDefinition(
            from: EvacuationConstants.kikikuruBotDefinitionUrl
        )
        await MainActor.run {
            settings.registerBot(definition)
            settings.bsafEnabled = true
            settings.evacuationEnabled = true
        }
        // 自動フォロー（既存の BsafBotsView と同じパターン）
        _ = try await graphService.follow(did: definition.bot.did)
    } catch {
        await MainActor.run {
            evacuationBotError = error.localizedDescription
        }
    }
    evacuationBotRegistering = false
}
```

4. **初回案内**（`evacuationOnboardingShown` が false の場合のみ表示）
   - 機能の存在を控えめに案内するシート or アラート。
   - オンを強制しない。「設定からいつでもオンにできます」のメッセージ。
   - 表示後 `evacuationOnboardingShown = true` に更新。

### 2.2 ファイル構成

| 新規 / 変更 | ファイル | 内容 |
|:--|:--|:--|
| 新規 | `scripts/build-shelters.py` | CSV → JSON 変換スクリプト |
| 新規 | `kazahana-ios/Resources/shelters.json` | 同梱避難所データ |
| 新規 | `kazahana-ios/Models/Shelter.swift` | `Shelter`, `ShelterHazards` モデル |
| 新規 | `kazahana-ios/Models/Prefecture.swift` | `Prefecture` enum（47都道府県） |
| 新規 | `kazahana-ios/Services/ShelterService.swift` | データ読み込み・最近傍探索 |
| 変更 | `kazahana-ios/Services/AppSettings.swift` | `evacuationEnabled` 等の設定追加 |
| 変更 | `kazahana-ios/Views/Settings/SettingsView.swift` | 避難誘導セクション追加 |

### 2.3 受け入れ条件

- [ ] CSV から正しい件数・座標・災害種別フラグで JSON に変換される
- [ ] 都道府県が `jp-xxxx` に正規化される（47都道府県すべて検証）
- [ ] `ShelterService.loadShelters()` が Bundle から正常にデコードできる
- [ ] 設定トグルが永続化され、デフォルト false
- [ ] 都道府県手動設定が永続化される
- [ ] bsaf-kikikuru-bot 未登録時にトグルON → 確認ダイアログが表示される
- [ ] 確認ダイアログ承認後、bsaf-kikikuru-bot が BSAF 登録 + 自動フォローされる
- [ ] 確認ダイアログでキャンセル → トグルは OFF のまま
- [ ] bsaf-kikikuru-bot 登録済みの場合、トグル ON は確認なしで即時有効化

### 2.4 注意点

- 国土地理院データは「最新でない場合・未掲載施設あり」。出典と注記を表示する準備をしておく（文言は Phase 5 で確定）。
- `shelters.json` のサイズが大きい場合、都道府県別に JSON を分割し、必要な都道府県のみ遅延ロードする最適化を検討。初期は全件読み込み + `[String: [Shelter]]`（都道府県キー）のインデックスを構築して検索を高速化する。

---

## 3. Phase 2: 位置情報取得 + 最寄り避難所表示 + OS ナビ委譲

### 3.1 タスク

1. **CoreLocation 導入**（`Services/LocationService.swift`）
   - `CLLocationManager` をラップしたサービスクラス。
   - `Info.plist` に `NSLocationWhenInUseUsageDescription` を記載（日本語・英語）。
   - **バックグラウンド常時測位は実装しない**。フォアグラウンド・オンデマンド測位のみ。
   - **アプリ全体で1インスタンス** とし、`@Environment` で注入する（複数 `CLLocationManager` の競合を防止）。
   - **`@Observable` と `NSObject` の併用問題** を回避するため、内部デリゲートクラスを分離する設計とする。

```swift
// Services/LocationService.swift

import CoreLocation

@Observable
final class LocationService {

    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var heading: Double = 0
    var headingAccuracy: Double = -1  // < 0 = キャリブレーション不良
    var errorMessage: String?

    private let manager = CLLocationManager()
    private var delegate: Delegate?

    init() {
        let delegate = Delegate(owner: self)
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// 現在地を一回取得（避難所一覧画面用）
    func requestLocation() {
        manager.requestLocation()
    }

    /// 連続測位を開始（コンパスナビ用：リアルタイム距離更新）
    func startUpdatingLocation() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10  // 10m ごとに更新（バッテリー節約）
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func startUpdatingHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stopUpdatingHeading() {
        manager.stopUpdatingHeading()
    }

    // MARK: - 内部デリゲート（NSObject 継承を分離）

    private class Delegate: NSObject, CLLocationManagerDelegate {
        private unowned let owner: LocationService

        init(owner: LocationService) {
            self.owner = owner
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            owner.currentLocation = locations.last?.coordinate
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            owner.heading = newHeading.trueHeading >= 0
                ? newHeading.trueHeading : newHeading.magneticHeading
            owner.headingAccuracy = newHeading.headingAccuracy
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            owner.errorMessage = error.localizedDescription
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            owner.authorizationStatus = manager.authorizationStatus
        }
    }
}
```

**注入方法**: `ContentView` レベルで1インスタンスを生成し、`.environment()` で配布する。避難誘導機能オフ時はインスタンスを生成しない（遅延初期化）。

```swift
// ContentView.swift での注入イメージ
@State private var locationService: LocationService? = nil

// evacuationEnabled が true になった時点で初期化
.onChange(of: settings.evacuationEnabled) { _, enabled in
    if enabled && locationService == nil {
        locationService = LocationService()
    }
}
```

2. **都道府県判定**
   - `CLGeocoder` で緯度経度から都道府県を逆ジオコーディング → `jp-xxxx` に変換。
   - `evacuationPrefectureOverride` が設定されていればそれを優先（測位不要）。

```swift
// ShelterService.swift に追加

/// CLGeocoder で都道府県を判定し jp-xxxx に変換
static func resolvePrefecture(from coordinate: CLLocationCoordinate2D) async -> String? {
    let geocoder = CLGeocoder()
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
          let state = placemarks.first?.administrativeArea
    else { return nil }
    return Prefecture.from(japaneseName: state)?.rawValue
}
```

3. **避難所詳細画面**（`Views/Evacuation/ShelterDetailView.swift`）
   - 施設名・対応災害種別・直線距離を表示。
   - 「地図アプリでナビ」ボタン。
   - 「簡易ナビ」ボタン（Phase 4 で接続）。

4. **最寄り避難所一覧画面**（`Views/Evacuation/NearestSheltersView.swift`）
   - `ShelterService.findNearest()` の結果をリスト表示。
   - 災害種別フィルタの選択 UI（洪水 / 土砂 / 地震 etc.）。

5. **OS ナビ委譲**（MapKit `MKMapItem`）
   - 避難所の座標で `MKMapItem` を生成し、`openInMaps(launchOptions:)` で Apple Maps の徒歩ナビを起動。

```swift
// ShelterService.swift に追加

import MapKit

/// Apple Maps で避難所への徒歩ナビを起動
static func openInMaps(shelter: Shelter) {
    let coordinate = CLLocationCoordinate2D(latitude: shelter.lat, longitude: shelter.lng)
    let placemark = MKPlacemark(coordinate: coordinate)
    let mapItem = MKMapItem(placemark: placemark)
    mapItem.name = shelter.name
    mapItem.openInMaps(launchOptions: [
        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
    ])
}
```

### 3.2 ファイル構成

| 新規 / 変更 | ファイル | 内容 |
|:--|:--|:--|
| 新規 | `kazahana-ios/Services/LocationService.swift` | CoreLocation ラッパー |
| 新規 | `kazahana-ios/Views/Evacuation/NearestSheltersView.swift` | 最寄り避難所一覧 |
| 新規 | `kazahana-ios/Views/Evacuation/ShelterDetailView.swift` | 避難所詳細 |
| 変更 | `kazahana-ios/Services/ShelterService.swift` | 都道府県判定・ナビ委譲追加 |
| 変更 | `kazahana-ios/Info.plist` | `NSLocationWhenInUseUsageDescription` 追加 |

### 3.3 受け入れ条件

- [ ] 位置情報の権限リクエストが正しく表示される
- [ ] 測位拒否時にクラッシュせず、手動都道府県設定にフォールバックできる
- [ ] `findNearest()` が災害種別フィルタを正しく適用する
- [ ] Haversine 距離が既知の2点で正しい（東京駅↔大阪駅 ≒ 401km 等）
- [ ] Apple Maps の徒歩ナビが実機で起動する

### 3.4 注意点

- 災害種別フィルタを外すと「津波非対応施設を津波時に案内」等の事故が起きる。フィルタは省略不可。
- `CLGeocoder` はオフラインで動作しない。オフライン時は手動設定の都道府県に依存するため、設定画面で手動設定を促す UX が重要。

---

## 4. Phase 3: BSAF 購読・バナー状態遷移

> **前提**: Phase 1 で bsaf-kikikuru-bot が BSAF 登録済み。タイムラインに同ボットの投稿が流れる状態。

### 4.1 タスク

1. **BSAF type → 災害種別マッピング**
   - bsaf-kikikuru-bot の `type` タグから、避難所検索時の災害種別フィルタを導出するテーブル。
   - 1つの type が複数の災害種別に対応する場合がある（例: 大雨 → 洪水 + 土砂 + 内水氾濫）。

```swift
// Services/EvacuationAlertService.swift

struct EvacuationAlertService {

    /// 避難レベルの value セット
    private static let alertValues: Set<String> = ["level3", "level4", "level5"]

    /// BSAF type → 対応する災害種別 KeyPath（OR 条件で適用）
    /// 1つの type が複数の災害種別に対応する場合がある
    static func hazardFilters(for bsafType: String) -> [KeyPath<ShelterHazards, Bool>] {
        switch bsafType {
        case "heavy-rain-warning":          return [\.flood, \.landslide, \.inlandFlood]
        case "flood-warning":               return [\.flood, \.inlandFlood]
        case "landslide-warning":           return [\.landslide]
        case "storm-surge-warning":         return [\.stormSurge]
        case "tsunami-warning":             return [\.tsunami]
        case "earthquake-warning":          return [\.earthquake]
        case "volcanic-warning":            return [\.volcano]
        default:
            // 未知の type は全種別を候補にする（安全側倒し）
            return [\.flood, \.landslide, \.stormSurge, \.earthquake,
                    \.tsunami, \.fire, \.inlandFlood, \.volcano]
        }
    }

    /// BSAF パース済みタグが避難誘導トリガーか判定
    static func isEvacuationTrigger(_ parsed: BsafParsedTags, prefecture: String) -> Bool {
        parsed.target == prefecture && alertValues.contains(parsed.value)
    }

    /// value 文字列を AlertLevel に変換
    static func toAlertLevel(_ value: String) -> AlertLevel? {
        AlertLevel(rawValue: value)
    }
}
```

> **注意**: `hazardFilters(for:)` のマッピングは bsaf-kikikuru-bot の実際の type 値を確認して確定すること。上記はイメージ。未知の type に対しては全種別を候補にする安全側倒しの設計。

2. **EvacuationViewModel**（`ViewModels/EvacuationViewModel.swift`）
   - バナー状態管理の中心。`@Observable`。
   - **`ContentView` レベルで保持** し、`MainTabView` の `.id(authVM.activeAccountDID)` によるリビルドの影響を受けないようにする。アカウント切替でバナーが消えるのは安全上の問題があるため。

```swift
// ViewModels/EvacuationViewModel.swift

@Observable
final class EvacuationViewModel {

    // MARK: - バナー状態
    var bannerVisible: Bool = false
    var highestLevel: AlertLevel? = nil
    var activeAlerts: [ActiveAlert] = []

    // MARK: - 設定参照
    private let settings: AppSettings

    /// タイムアウト時間（時間）。cancelled 見逃し対策。
    private let alertTimeoutHours: Double = 6.0

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - アラート処理

    /// BSAF 投稿を処理し、バナー状態を更新
    @MainActor
    func processPost(tags: BsafParsedTags) {
        guard settings.evacuationEnabled else { return }

        let prefecture = resolvedPrefecture()
        guard let prefecture else { return }

        // cancelled 処理
        if tags.value == "cancelled" {
            removeCancelledAlerts(type: tags.type, target: tags.target)
            return
        }

        // レベル3以上の判定
        guard EvacuationAlertService.isEvacuationTrigger(tags, prefecture: prefecture) else { return }
        guard let level = EvacuationAlertService.toAlertLevel(tags.value) else { return }

        let alert = ActiveAlert(
            type: tags.type,
            value: level,
            time: tags.time,
            target: tags.target,
            receivedAt: Date()
        )

        // 重複排除（type + value + time + target の完全一致）
        guard !activeAlerts.contains(where: { $0.id == alert.id }) else { return }

        activeAlerts.append(alert)
        updateBannerState()
    }

    /// タイムアウトした古いアラートを除去
    @MainActor
    func expireStaleAlerts() {
        let cutoff = Date().addingTimeInterval(-alertTimeoutHours * 3600)
        activeAlerts.removeAll { $0.receivedAt < cutoff }
        updateBannerState()
    }

    // MARK: - Private

    private func resolvedPrefecture() -> String? {
        settings.evacuationPrefectureOverride
        // 位置情報由来の都道府県は LocationService 経由で外部から設定する拡張余地あり
    }

    @MainActor
    private func removeCancelledAlerts(type: String, target: String) {
        activeAlerts.removeAll { $0.type == type && $0.target == target }
        updateBannerState()
    }

    @MainActor
    private func updateBannerState() {
        if activeAlerts.isEmpty {
            bannerVisible = false
            highestLevel = nil
        } else {
            bannerVisible = true
            highestLevel = activeAlerts.map(\.value).max()
        }
    }
}
```

**配置**:

```swift
// ContentView.swift（MainTabView の外側）
@State private var evacuationVM = EvacuationViewModel(settings: .shared)

MainTabView(client: authVM.client, evacuationVM: evacuationVM)
    .id(authVM.activeAccountDID) // ← これでリビルドされても evacuationVM は生き残る
```

3. **タイムアウト失効**（`scenePhase` + Timer 併用）
   - `Timer` で定期的に `expireStaleAlerts()` を呼び出す（例: 10分間隔）。
   - **アプリがバックグラウンドに入ると Timer は停止する** ため、`scenePhase` が `.active` に戻った時点でも失効チェックを再実行する。

```swift
// ContentView.swift
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active {
        evacuationVM.expireStaleAlerts()
    }
}
.task {
    // 10分間隔でタイムアウトチェック
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(600))
        await evacuationVM.expireStaleAlerts()
    }
}
```

4. **バナー UI**（`Views/Evacuation/EvacuationBannerView.swift`）
   - `ContentView` の `.overlay(alignment: .bottom)` でタブバーの上に常駐（`MainTabView` の内側ではなく外側）。
   - level3: 控えめな黄色系。「警報級の気象情報が出ています。最寄り避難所を見る >」
   - level4/5: 赤系の強調表示。タップで避難所一覧画面へ遷移。

```swift
// Views/Evacuation/EvacuationBannerView.swift

struct EvacuationBannerView: View {
    let highestLevel: AlertLevel
    let prefectureName: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: highestLevel >= .level4 ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "evacuation.bannerTitle.\(highestLevel.rawValue)"))
                        .font(.subheadline.weight(.semibold))
                    Text(prefectureName)
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bannerColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var bannerColor: Color {
        switch highestLevel {
        case .level3: return Color(hex: 0xCA8A04)  // 黄系
        case .level4: return Color(hex: 0xDC2626)  // 赤系
        case .level5: return Color(hex: 0xBE185D)  // ピンク系（特別警報級）
        }
    }
}
```

5. **タイムラインとの統合**
   - `TimelineViewModel` でフィードを読み込む際、bsaf-kikikuru-bot の投稿の BSAF タグを `EvacuationViewModel.processPost()` に渡す。
   - 既存の `BsafService.parseBsafTags()` の結果を流用。
   - `EvacuationViewModel` は `TimelineViewModel` の init パラメータとして渡す（疎結合を維持）。

### 4.2 ファイル構成

| 新規 / 変更 | ファイル | 内容 |
|:--|:--|:--|
| 新規 | `kazahana-ios/Models/EvacuationAlert.swift` | `AlertLevel`, `ActiveAlert` モデル |
| 新規 | `kazahana-ios/Services/EvacuationAlertService.swift` | トリガー判定・災害種別マッピング |
| 新規 | `kazahana-ios/ViewModels/EvacuationViewModel.swift` | バナー状態管理 |
| 新規 | `kazahana-ios/Views/Evacuation/EvacuationBannerView.swift` | バナー UI |
| 変更 | `kazahana-ios/ContentView.swift` | EvacuationVM 保持・バナー overlay・scenePhase |
| 変更 | `kazahana-ios/ViewModels/TimelineViewModel.swift` | BSAF タグを EvacuationVM に転送 |

### 4.3 受け入れ条件

- [ ] 現在地都道府県以外の target でバナーが出ない
- [ ] level3 検知でバナー出現、level4 昇格で強調
- [ ] `cancelled` でバナーが消える
- [ ] タイムアウトで自動失効する
- [ ] フォアグラウンド復帰時にタイムアウト済みアラートが即座に除去される
- [ ] 複数現象同時発令で表示が破綻しない
- [ ] 機能オフ時は購読・バナーとも無効
- [ ] アカウント切替後もバナー状態が維持される
- [ ] BSAF type から正しい災害種別フィルタが導出される

### 4.4 遅延の扱い

- bsaf-kikikuru-bot は10分間隔ポーリング。kazahana-ios のタイムライン更新もポーリング（`timelinePollingInterval`: 30〜120秒）。最大10分超の遅延は許容（レベル3先回り表示のため）。

---

## 5. Phase 4: kazahana 内簡易ナビ + オフライン挙動

### 5.1 タスク

1. **方位角計算**（`ShelterService` に追加）
   - 現在地と避難所座標から方位角（bearing）を計算する関数。

```swift
// ShelterService.swift に追加

/// 2点間の方位角を計算（度、真北基準で時計回り）
static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
    let dLng = (end.longitude - start.longitude) * .pi / 180
    let lat1 = start.latitude * .pi / 180
    let lat2 = end.latitude * .pi / 180
    let y = sin(dLng) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
    let bearing = atan2(y, x) * 180 / .pi
    return (bearing + 360).truncatingRemainder(dividingBy: 360) // 0-360
}
```

2. **コンパス連携**
   - Phase 2 で作成した共有 `LocationService` の `startUpdatingHeading()` / `startUpdatingLocation()` を使用。
   - heading + 連続測位（10m 間隔）を組み合わせ、歩行中にリアルタイムで矢印と距離が更新される。
   - heading / 連続測位は **コンパスナビ画面表示中のみ** 有効にし、離脱時に確実に停止する（バッテリー節約）。

3. **簡易ナビ UI**（`Views/Evacuation/CompassNavView.swift`）
   - 共有 `LocationService` を `@Environment` で受け取る（独自インスタンスを生成しない）。
   - 避難所方向の矢印（方位角 − デバイス向き = 回転角度）。
   - 直線距離をリアルタイム更新。
   - 磁気センサのキャリブレーション不良時の精度警告。
   - **macOS Catalyst ではコンパスが使えない** ため、`#if !targetEnvironment(macCatalyst)` で分岐し、Mac では Apple Maps への委譲のみ提供する。

```swift
// Views/Evacuation/CompassNavView.swift

struct CompassNavView: View {
    let shelter: Shelter
    @Environment(LocationService.self) private var locationService

    var body: some View {
        VStack(spacing: 24) {
            Text(shelter.name)
                .font(.headline)

            #if !targetEnvironment(macCatalyst)
            // 矢印（避難所方向）
            Image(systemName: "location.north.fill")
                .font(.system(size: 80))
                .rotationEffect(.degrees(arrowRotation))
                .animation(.easeInOut(duration: 0.3), value: arrowRotation)
                .foregroundStyle(.blue)

            // 精度警告
            if locationService.headingAccuracy < 0 {
                Label(String(localized: "evacuation.compassCalibration"),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            #else
            // macOS: コンパス非対応メッセージ
            ContentUnavailableView {
                Label(String(localized: "evacuation.compassUnavailableMac"),
                      systemImage: "location.slash")
            } description: {
                Text(String(localized: "evacuation.useMapAppInstead"))
            }
            #endif

            // 直線距離（プラットフォーム共通）
            if let location = locationService.currentLocation {
                let dist = ShelterService.haversineDistance(
                    lat1: location.latitude, lng1: location.longitude,
                    lat2: shelter.lat, lng2: shelter.lng
                )
                Text(formatDistance(dist))
                    .font(.title2.weight(.semibold))
            }

            // 免責（Phase 5 で文言確定）
            Text(String(localized: "evacuation.compassDisclaimer"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .onAppear {
            locationService.startUpdatingLocation()
            locationService.startUpdatingHeading()
        }
        .onDisappear {
            locationService.stopUpdatingLocation()
            locationService.stopUpdatingHeading()
        }
    }

    private var arrowRotation: Double {
        guard let location = locationService.currentLocation else { return 0 }
        let target = CLLocationCoordinate2D(latitude: shelter.lat, longitude: shelter.lng)
        let bearing = ShelterService.bearing(from: location, to: target)
        return bearing - locationService.heading
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
```

4. **オフライン挙動**
   - `NWPathMonitor`（Network framework）で通信状態を監視。
   - オフライン時: OS ナビボタンを非活性にし、簡易ナビへ誘導する導線を優先表示。
   - 同梱データ + コンパスは通信不要のため動作保証。
   - **`CLGeocoder`（都道府県判定）はオフライン不可**。オフライン時は手動設定の都道府県に依存する。設定画面で手動設定を促す UX を用意し、オフライン時に「都道府県を設定してください」と案内する。

### 5.2 ファイル構成

| 新規 / 変更 | ファイル | 内容 |
|:--|:--|:--|
| 新規 | `kazahana-ios/Views/Evacuation/CompassNavView.swift` | 簡易コンパスナビ |
| 変更 | `kazahana-ios/Services/ShelterService.swift` | 方位角計算追加 |
| 変更 | `kazahana-ios/Views/Evacuation/ShelterDetailView.swift` | オフラインフォールバック導線追加 |

### 5.3 受け入れ条件

- [ ] 方位角計算が既知座標で正しい（例: 東京→大阪 ≒ 249°）
- [ ] コンパスが実機で動作し、矢印が端末の向きに追従する
- [ ] 歩行中に直線距離がリアルタイムで更新される
- [ ] 機内モード（オフライン）で簡易ナビが動作する（実機確認）
- [ ] オフライン時に OS ナビではなく簡易ナビへ誘導される
- [ ] macOS Catalyst でコンパスナビがクラッシュしない（グレースフル degradation）
- [ ] コンパスナビ画面離脱時に連続測位 + heading 更新が停止する（バッテリー確認）

### 5.4 注意点

- 磁気センサのキャリブレーション不良（`headingAccuracy < 0`）時に精度警告を表示すること。
- macOS Catalyst ではコンパスが使えない。Apple Maps 委譲のみ提供。
- `CLGeocoder` はオフライン不可。都道府県の手動設定をオフライン時の代替手段として明確に案内する。

---

## 6. Phase 5: 免責文言確定・ストア審査対応

### 6.1 免責・文言（必須）

1. バナー近傍と設定画面に免責の一文を表示。
   - 例:「この情報は気象庁の危険度情報（警報級）に基づく補助です。避難の判断は自治体の避難指示や公式情報をご確認ください。」
2. 避難所データに国土地理院出典と「最新でない場合がある」注記。
3. 「自治体の避難指示そのものではない」性質の明示。
4. **専門家確認**: 表示文言・免責・責任範囲をリリース前に専門家（弁護士、可能なら防災に明るい者）に通すこと。← この確認完了をリリース条件とする。

### 6.2 ストア審査（Apple）

- `Info.plist` の `NSLocationWhenInUseUsageDescription` に目的を明記:
  - 日本語:「最寄りの避難所を検索し、避難誘導を行うために使用します」
  - 英語: "Used to find the nearest evacuation shelter and provide navigation assistance"
- App Store Connect のプライバシー詳細で「位置情報」→「アプリの機能」として記載。
- App Review 向けのデモ手順を準備（BSAF ボットの投稿を確認する方法等）。
- Michi-Navi の審査ノウハウを流用。

### 6.3 受け入れ条件

- [ ] 免責文言が表示される（バナー近傍・設定画面・避難所詳細）
- [ ] 出典・注記が表示される
- [ ] 専門家確認が完了している（リリースゲート）
- [ ] ストア審査用の説明文が準備済み

### 6.4 実装結果（iOS）

- **オンボーディングダイアログ**: `ContentView` の `.onAppear` で `evacuationOnboardingShown == false && !evacuationEnabled` を判定し `.alert()` で表示。ボタンは「あとで」のみ。
- **デモモード（ストア審査対応）**: `#if DEBUG` のデバッグボタンを廃止し、設定画面のバージョン番号を5回タップで表示される隠しデモモードに変更。Release ビルドでも App Review 審査官がアラートバナーをシミュレーション可能。
  - `SettingsView`: `demoModeTapCount` / `showDemoMode` State で制御
  - `EvacuationViewModel.injectTestAlert()` から `#if DEBUG` を除去
- **ローカライズ**: `evacuation.*` 49キー（JA/EN 2言語）。11言語展開は将来対応。
- **免責文言表示箇所**: CompassNavView、NearestSheltersView、ShelterDetailView の3画面 + 設定セクション footer
- **専門家確認**: 弁護士・防災専門家による文言・免責・責任範囲の確認完了（2026-06-04）
- **バージョン**: v3.2.0 (build 17)

---

## 7. 全体の受け入れ条件（リリース判定）

- [x] Phase 1〜5 の各受け入れ条件をすべて満たす
- [x] 機能オフ時、位置情報取得・購読・バナーがすべて無効であることを確認
- [x] オフライン（機内モード）で「避難所データ閲覧 + 最寄り探索 + 簡易ナビ」が動作
- [x] iOS 実機での通し動作確認
- [x] macOS Catalyst での挙動確認（コンパスナビは非対応 → Apple Maps 委譲のみ。クラッシュしないこと）
- [x] アカウント切替後もバナー状態が維持されることを確認
- [x] 免責・専門家確認が完了
- [x] PLATFORM_MATRIX.md 更新（Desktop 非対象 / iOS 対象 / Android 対象）
- [x] バージョン bump（位置情報基盤追加のため minor bump 想定）

---

## 8. テスト方針

| 種別 | 対象 |
|:--|:--|
| ユニット | CSV 変換、都道府県正規化（47件）、Haversine 距離（既知2点）、災害種別フィルタ、方位角計算、バナー状態遷移（昇格・解除・タイムアウト・重複排除） |
| 結合 | BSAF タグ受信 → バナー表示 → 避難所詳細 → ナビ委譲の一連フロー |
| 実機 | 位置情報権限、Apple Maps ナビ起動、コンパス追従、オフライン簡易ナビ |
| 異常系 | 測位拒否、データ未該当（海外座標等）、cancelled 見逃し（タイムアウト）、複数現象同時、コンパス非対応端末 |

---

## 9. 実装順序の推奨

1. **Phase 1**（データ基盤・設定）→ 単体で価値が出る最小単位
2. **Phase 2**（測位・最寄り・OS ナビ）→ 手動操作での避難所案内が成立
3. **Phase 3**（BSAF・バナー）→ 自動検知の動線が加わる
4. **Phase 4**（簡易ナビ・オフライン）→ オフライン耐性の最終防衛線
5. **Phase 5**（免責・審査）→ リリース準備

> Phase 1〜2 完了時点で「手動で最寄り避難所を調べてナビする」最小機能としてリリース可能。Phase 3 以降は段階的に上乗せできる構成です。

---

## 10. 多言語対応（追加キー）

`Localizable.xcstrings` に追加。既存の `String(localized:)` パターンに準拠。

| キー | 日本語 | 英語 |
|:--|:--|:--|
| `evacuation.title` | 避難誘導 | Evacuation Assist |
| `evacuation.enable` | 避難誘導機能を有効にする | Enable Evacuation Assist |
| `evacuation.footer` | 気象庁の警報級・危険度情報に基づき、最寄りの避難所情報を表示します。本機能は bsaf-kikikuru-bot の BSAF 登録を前提としています。 | Shows nearby shelter information based on JMA weather warning levels. Requires bsaf-kikikuru-bot BSAF registration. |
| `evacuation.botConfirm.title` | bsaf-kikikuru-bot の登録 | Register bsaf-kikikuru-bot |
| `evacuation.botConfirm.message` | 避難誘導機能は bsaf-kikikuru-bot の BSAF 登録を前提とした機能です。有効化すると bsaf-kikikuru-bot を自動的に BSAF 登録し、フォローします。 | Evacuation Assist requires bsaf-kikikuru-bot BSAF registration. Enabling this will automatically register and follow bsaf-kikikuru-bot. |
| `evacuation.botConfirm.enable` | 有効化する | Enable |
| `evacuation.prefectureOverride` | 都道府県（手動設定） | Prefecture (manual) |
| `evacuation.prefectureAuto` | 自動（位置情報から判定） | Auto (from location) |
| `evacuation.bannerTitle.level3` | 警報級の気象情報が出ています | Weather warning level information issued |
| `evacuation.bannerTitle.level4` | 避難情報の確認を | Check evacuation information |
| `evacuation.bannerTitle.level5` | 直ちに安全確保を | Secure safety immediately |
| `evacuation.nearestShelters` | 最寄り避難所 | Nearest Shelters |
| `evacuation.openInMaps` | 地図アプリでナビ | Navigate with Maps |
| `evacuation.compassNav` | 簡易ナビ（コンパス） | Simple Nav (Compass) |
| `evacuation.compassDisclaimer` | コンパスの精度は環境に依存します。目安としてご利用ください。 | Compass accuracy depends on conditions. Use as a guide only. |
| `evacuation.disclaimer` | この情報は気象庁の危険度情報に基づく補助です。避難の判断は自治体の避難指示や公式情報をご確認ください。 | This is supplementary information based on JMA hazard levels. Please check official evacuation orders for decisions. |
| `evacuation.dataSource` | 出典: 国土地理院 指定緊急避難場所データ | Source: GSI Designated Emergency Evacuation Sites |
| `evacuation.dataWarning` | 最新でない場合があります。最新情報は自治体にご確認ください。 | May not be up to date. Check with local authorities for the latest. |
| `evacuation.onboarding.title` | 避難誘導機能について | About Evacuation Assist |
| `evacuation.onboarding.message` | 気象警報時に最寄りの避難所を案内する機能が利用できます。設定からいつでもオンにできます。 | A feature to guide you to the nearest shelter during weather warnings is available. You can enable it anytime in Settings. |
| `evacuation.onboarding.dismiss` | あとで | Later |
| `evacuation.offline` | オフライン | Offline |
| `evacuation.offlineNote` | 通信できません。簡易ナビをご利用ください。 | No connection. Please use the simple compass navigator. |
| `evacuation.hazard.flood` | 洪水 | Flood |
| `evacuation.hazard.landslide` | 土砂災害 | Landslide |
| `evacuation.hazard.stormSurge` | 高潮 | Storm Surge |
| `evacuation.hazard.earthquake` | 地震 | Earthquake |
| `evacuation.hazard.tsunami` | 津波 | Tsunami |
| `evacuation.hazard.fire` | 大規模火事 | Large Fire |
| `evacuation.hazard.inlandFlood` | 内水氾濫 | Inland Flood |
| `evacuation.hazard.volcano` | 火山 | Volcano |
| `evacuation.compassCalibration` | コンパスの精度が低下しています。端末を8の字に動かしてください。 | Compass accuracy is low. Move your device in a figure-8 pattern. |
| `evacuation.compassUnavailableMac` | コンパスはこのデバイスでは利用できません | Compass is not available on this device |
| `evacuation.useMapAppInstead` | 地図アプリでのナビをご利用ください。 | Please use the Maps app for navigation. |
| `evacuation.setPrefecturePrompt` | オフラインで利用するには、都道府県を手動設定してください。 | To use offline, please set your prefecture manually. |

---

## 出典

| 情報 | URL |
|:--|:--|
| 国土地理院 指定緊急避難場所・指定避難所データ | https://www.gsi.go.jp/bousaichiri/hinanbasho.html |
| 同 データダウンロード | https://hinanmap.gsi.go.jp/index.html |
| bsaf-kikikuru-bot | https://github.com/osprey74/bsaf-kikikuru-bot |
| BSAF Protocol | https://github.com/osprey74/bsaf-protocol |
| Apple CoreLocation | https://developer.apple.com/documentation/corelocation |
| Apple MapKit | https://developer.apple.com/documentation/mapkit |

---

## 11. Android 実装への申し送り事項

iOS 実装で得られた知見を Android 実装に引き継ぐ。

### データ形式
- 避難所データは CSV → コンパクト JSON（`id` 除去、`hazards` をビットマスク化）→ zlib 圧縮。115,447件で 2.1MB。
- 変換スクリプト: `scripts/build-shelters.py`（iOS/Android 共用可）。出力をそのまま Android の assets に配置可能。

### ストア審査
- **デモモード方式を推奨**: `#if DEBUG` や `BuildConfig.DEBUG` ではなく、設定画面のバージョン番号タップ等の隠しジェスチャーで Release ビルドでもデモ可能にする。Google Play 審査でも同様の手順を審査ノートに記載できる。
- 審査ノート例: 「Settings > App Info > tap version 5 times to enable demo mode. Use Demo buttons in Evacuation Assist section to simulate alerts.」

### Bot 定義 URL
- `https://raw.githubusercontent.com/osprey74/bsaf-kikikuru-bot/main/bsaf-bot.json`（GitHub raw URL）。GitHub の blob URL ではなく raw URL を使用すること。

### オンボーディング
- 初回起動時に1回だけダイアログ表示。SharedPreferences 等で `evacuationOnboardingShown` フラグを管理。

### Bluesky 公式アカウント
- `@kazahana.app`（旧 `@app-kazahana.bsky.social` から変更済み）
