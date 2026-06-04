// ShelterStore.swift
// kazahana-ios
// 避難所データのメモリキャッシュ（@Observable で Environment 配布）

import Foundation
import Observation

@Observable
final class ShelterStore {
    /// 都道府県別の避難所インデックス
    var index: [String: [Shelter]] = [:]

    /// データが読み込み済みか
    var isLoaded: Bool { !index.isEmpty }

    /// Bundle から避難所データを読み込む（未読み込みの場合のみ）
    func loadIfNeeded() {
        guard !isLoaded else { return }
        index = ShelterService.loadShelters()
    }
}
