#!/usr/bin/env python3
"""
国土地理院 指定緊急避難場所データ CSV → shelters.json 変換スクリプト

使い方:
  1. https://hinanmap.gsi.go.jp/index.html から全国版 CSV をダウンロード
  2. python3 scripts/build-shelters.py <input.csv> [output.json]
     - output.json を省略すると kazahana-ios/Resources/shelters.json に出力

入力 CSV のエンコーディング: Shift_JIS（国土地理院デフォルト）
"""

import csv
import json
import sys
import os
from pathlib import Path

# 都道府県名 → jp-xxxx マッピング
PREFECTURE_MAP = {
    "北海道": "jp-hokkaido",
    "青森県": "jp-aomori",
    "岩手県": "jp-iwate",
    "宮城県": "jp-miyagi",
    "秋田県": "jp-akita",
    "山形県": "jp-yamagata",
    "福島県": "jp-fukushima",
    "茨城県": "jp-ibaraki",
    "栃木県": "jp-tochigi",
    "群馬県": "jp-gunma",
    "埼玉県": "jp-saitama",
    "千葉県": "jp-chiba",
    "東京都": "jp-tokyo",
    "神奈川県": "jp-kanagawa",
    "新潟県": "jp-niigata",
    "富山県": "jp-toyama",
    "石川県": "jp-ishikawa",
    "福井県": "jp-fukui",
    "山梨県": "jp-yamanashi",
    "長野県": "jp-nagano",
    "岐阜県": "jp-gifu",
    "静岡県": "jp-shizuoka",
    "愛知県": "jp-aichi",
    "三重県": "jp-mie",
    "滋賀県": "jp-shiga",
    "京都府": "jp-kyoto",
    "大阪府": "jp-osaka",
    "兵庫県": "jp-hyogo",
    "奈良県": "jp-nara",
    "和歌山県": "jp-wakayama",
    "鳥取県": "jp-tottori",
    "島根県": "jp-shimane",
    "岡山県": "jp-okayama",
    "広島県": "jp-hiroshima",
    "山口県": "jp-yamaguchi",
    "徳島県": "jp-tokushima",
    "香川県": "jp-kagawa",
    "愛媛県": "jp-ehime",
    "高知県": "jp-kochi",
    "福岡県": "jp-fukuoka",
    "佐賀県": "jp-saga",
    "長崎県": "jp-nagasaki",
    "熊本県": "jp-kumamoto",
    "大分県": "jp-oita",
    "宮崎県": "jp-miyazaki",
    "鹿児島県": "jp-kagoshima",
    "沖縄県": "jp-okinawa",
}

# 国土地理院 CSV の災害種別列インデックス（0始まり）
# CSV 列構成は年度により変わる可能性があるため、実際のヘッダーを確認して調整すること
# 一般的な列構成:
#   0: No
#   1: 施設・場所名
#   2: 住所
#   3: 都道府県名又は都道府県コード
#   4: 市区町村名又は市区町村コード
#   5: 緯度
#   6: 経度
#   以降: 各災害種別フラグ（1=対応, 0 or 空=非対応）
#
# 災害種別列の実際のインデックスは CSV ヘッダーで確認
HAZARD_COLUMNS = {
    "flood": None,        # 洪水
    "landslide": None,    # 崖崩れ、土石流及び地滑り
    "stormSurge": None,   # 高潮
    "earthquake": None,   # 地震
    "tsunami": None,      # 津波
    "fire": None,         # 大規模な火事
    "inlandFlood": None,  # 内水氾濫
    "volcano": None,      # 火山現象
}

# ヘッダーのキーワード → hazard key マッピング
HAZARD_HEADER_KEYWORDS = {
    "洪水": "flood",
    "崖崩れ": "landslide",
    "土石流": "landslide",
    "地滑り": "landslide",
    "高潮": "stormSurge",
    "地震": "earthquake",
    "津波": "tsunami",
    "火事": "fire",
    "内水氾濫": "inlandFlood",
    "火山": "volcano",
}


def detect_hazard_columns(headers: list[str]) -> dict[str, int]:
    """ヘッダー行から災害種別列のインデックスを自動検出"""
    mapping = {}
    for idx, header in enumerate(headers):
        for keyword, hazard_key in HAZARD_HEADER_KEYWORDS.items():
            if keyword in header and hazard_key not in mapping:
                mapping[hazard_key] = idx
    return mapping


def to_bool(val: str) -> bool:
    """CSV の値を bool に変換（"1", "○" 等 → True）"""
    return val.strip() in ("1", "○", "true", "True", "TRUE")


def detect_encoding(filepath: str) -> str:
    """ファイルのエンコーディングを推定"""
    for enc in ["utf-8-sig", "utf-8", "shift_jis", "cp932"]:
        try:
            with open(filepath, encoding=enc) as f:
                f.read(1024)
            return enc
        except (UnicodeDecodeError, UnicodeError):
            continue
    return "utf-8"


def detect_prefecture_column(headers: list[str]) -> int | None:
    """都道府県列を自動検出"""
    for idx, h in enumerate(headers):
        if "都道府県" in h:
            return idx
    return None


def detect_name_column(headers: list[str]) -> int | None:
    """施設名列を自動検出"""
    for idx, h in enumerate(headers):
        if "施設" in h or "場所" in h or "名称" in h:
            return idx
    return None


def detect_coord_columns(headers: list[str]) -> tuple[int | None, int | None]:
    """緯度・経度列を自動検出"""
    lat_col = None
    lng_col = None
    for idx, h in enumerate(headers):
        if "緯度" in h and lat_col is None:
            lat_col = idx
        if "経度" in h and lng_col is None:
            lng_col = idx
    return lat_col, lng_col


def convert(input_path: str, output_path: str):
    encoding = detect_encoding(input_path)
    print(f"Detected encoding: {encoding}")

    with open(input_path, encoding=encoding, newline="") as f:
        reader = csv.reader(f)
        headers = next(reader)

    # 列の自動検出
    pref_col = detect_prefecture_column(headers)
    name_col = detect_name_column(headers)
    lat_col, lng_col = detect_coord_columns(headers)
    hazard_cols = detect_hazard_columns(headers)

    print(f"Headers: {headers[:10]}...")
    print(f"Prefecture col: {pref_col} ({headers[pref_col] if pref_col is not None else 'NOT FOUND'})")
    print(f"Name col: {name_col} ({headers[name_col] if name_col is not None else 'NOT FOUND'})")
    print(f"Lat col: {lat_col}, Lng col: {lng_col}")
    print(f"Hazard columns: {hazard_cols}")

    if pref_col is None or name_col is None or lat_col is None or lng_col is None:
        print("ERROR: Could not detect required columns. Please check CSV format.")
        print("Expected columns: 都道府県, 施設/場所名, 緯度, 経度")
        sys.exit(1)

    missing_hazards = [k for k in HAZARD_COLUMNS if k not in hazard_cols]
    if missing_hazards:
        print(f"WARNING: Could not detect hazard columns: {missing_hazards}")
        print("These will default to false for all shelters.")

    shelters = []
    skipped = 0

    with open(input_path, encoding=encoding, newline="") as f:
        reader = csv.reader(f)
        next(reader)  # skip header

        for row_num, row in enumerate(reader, start=2):
            try:
                pref_name = row[pref_col].strip()
                pref_code = PREFECTURE_MAP.get(pref_name)
                if not pref_code:
                    skipped += 1
                    continue

                lat_str = row[lat_col].strip()
                lng_str = row[lng_col].strip()
                if not lat_str or not lng_str:
                    skipped += 1
                    continue

                lat = float(lat_str)
                lng = float(lng_str)

                name = row[name_col].strip()
                if not name:
                    skipped += 1
                    continue

                hazards = {}
                for hazard_key in HAZARD_COLUMNS:
                    col_idx = hazard_cols.get(hazard_key)
                    if col_idx is not None and col_idx < len(row):
                        hazards[hazard_key] = to_bool(row[col_idx])
                    else:
                        hazards[hazard_key] = False

                shelter = {
                    "id": f"{pref_code}-{row_num}",
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "prefecture": pref_code,
                    "hazards": hazards,
                }
                shelters.append(shelter)

            except (IndexError, ValueError) as e:
                print(f"WARNING: Skipping row {row_num}: {e}")
                skipped += 1

    # 出力
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(shelters, f, ensure_ascii=False, separators=(",", ":"))

    file_size = os.path.getsize(output_path)
    pref_counts = {}
    for s in shelters:
        pref_counts[s["prefecture"]] = pref_counts.get(s["prefecture"], 0) + 1

    print(f"\nConversion complete:")
    print(f"  Total shelters: {len(shelters)}")
    print(f"  Skipped rows: {skipped}")
    print(f"  Prefectures: {len(pref_counts)}")
    print(f"  Output size: {file_size / 1024 / 1024:.2f} MB")
    print(f"  Output: {output_path}")

    if len(pref_counts) < 47:
        print(f"\n  WARNING: Only {len(pref_counts)}/47 prefectures found!")
        missing = set(PREFECTURE_MAP.values()) - set(pref_counts.keys())
        print(f"  Missing: {missing}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 build-shelters.py <input.csv> [output.json]")
        print("  input.csv: 国土地理院 指定緊急避難場所 CSV")
        print("  output.json: 出力先 (default: kazahana-ios/Resources/shelters.json)")
        sys.exit(1)

    input_path = sys.argv[1]
    script_dir = Path(__file__).parent
    default_output = script_dir.parent / "kazahana-ios" / "Resources" / "shelters.json"
    output_path = sys.argv[2] if len(sys.argv) > 2 else str(default_output)

    convert(input_path, output_path)
