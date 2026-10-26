// FeedManagementView.swift
// kazahana-ios
// ホームフィード管理画面（表示/非表示・並び替え）

import SwiftUI

struct FeedManagementView: View {

    private let feedService: FeedService
    private let actorDID: String
    @Environment(AppSettings.self) private var settings

    @State private var isLoading = false
    @State private var visibleItems: [FeedItem] = []
    @State private var hiddenItems: [FeedItem] = []
    /// インクリメントすると .task(id:) が再実行されリフレッシュされる
    @State private var refreshID = 0

    /// フィード/リストを統一的に扱うための内部モデル
    struct FeedItem: Identifiable, Equatable {
        let id: String      // URI
        let name: String
        let icon: String
        let isListType: Bool  // true = リスト, false = カスタムフィード

        /// 非表示セクション用の行 ID。表示セクションと同じ ID だと、表示に切り替えた行が
        /// 非表示セクションの行（並び替えなし）として使い回され、ハンドルが付かない
        var hiddenRowID: String { "hidden:" + id }
    }

    init(client: ATProtoClient, actorDID: String) {
        self.feedService = FeedService(client: client)
        self.actorDID = actorDID
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            // 「全フィードをメニューに表示」トグル
            Section {
                Toggle(String(localized: "settings.showAllFeedsInSelector"),
                       isOn: $settings.showAllFeedsInSelector)
            } footer: {
                Text(String(localized: "settings.showAllFeedsInSelectorFooter"))
                    .font(.caption)
            }

            // 表示フィード（ドラッグで並び替え可能）
            if !visibleItems.isEmpty {
                Section(String(localized: "settings.visibleFeeds")) {
                    #if targetEnvironment(macCatalyst)
                    // macOS 27 の Catalyst ではドラッグのドロップが確定しないため（.onMove /
                    // .dropDestination とも）、行の上下ボタンで並び替える
                    ForEach(visibleItems) { item in
                        feedItemRow(item: item, isHidden: false)
                    }
                    #else
                    ForEach(visibleItems) { item in
                        feedItemRow(item: item, isHidden: false)
                    }
                    .onMove { from, to in
                        visibleItems.move(fromOffsets: from, toOffset: to)
                        saveOrder()
                    }
                    #endif
                }
            }

            // 非表示フィード
            if !hiddenItems.isEmpty {
                Section(String(localized: "settings.hiddenFeeds")) {
                    ForEach(hiddenItems, id: \.hiddenRowID) { item in
                        feedItemRow(item: item, isHidden: true)
                    }
                }
            }

            // ローディング / 空状態
            if visibleItems.isEmpty && hiddenItems.isEmpty {
                Section {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    } else {
                        Text(String(localized: "settings.noFeedsOrLists"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.feedManagement"))
        .navigationBarTitleDisplayMode(.inline)
        #if !targetEnvironment(macCatalyst)
        .environment(\.editMode, .constant(.active))
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    visibleItems = []
                    hiddenItems = []
                    refreshID += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task(id: refreshID) {
            await loadItems()
        }
    }

    // MARK: - フィード行

    @ViewBuilder
    private func feedItemRow(item: FeedItem, isHidden: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                Text(item.isListType
                     ? String(localized: "feed.typeList")
                     : String(localized: "feed.typeCustomFeed"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            #if targetEnvironment(macCatalyst)
            if !isHidden, let index = visibleItems.firstIndex(of: item) {
                Button {
                    moveItem(at: index, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .accessibilityLabel(String(localized: "settings.moveUp"))

                Button {
                    moveItem(at: index, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == visibleItems.count - 1)
                .accessibilityLabel(String(localized: "settings.moveDown"))
            }
            #endif

            // 表示/非表示トグルボタン
            Button {
                toggleVisibility(uri: item.id)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
        }
        .opacity(isHidden ? 0.6 : 1.0)
    }

    // MARK: - Data Loading

    private func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await feedService.getAllSavedFeedItems(actor: actorDID)
            guard !Task.isCancelled else { return }
            let feedItems: [FeedItem] = result.feeds.map {
                FeedItem(id: $0.uri, name: $0.displayName, icon: "list.star", isListType: false)
            }
            let listItems: [FeedItem] = result.lists.map {
                FeedItem(id: $0.uri, name: $0.name, icon: "list.bullet.rectangle", isListType: true)
            }
            buildItemLists(all: feedItems + listItems)
        } catch {
            print("[FeedManagementView] load error: \(error)")
        }
    }

    private func buildItemLists(all: [FeedItem]) {
        let feedOrder = settings.pinnedFeedURIs
        let hiddenURIs = Set(settings.hiddenFeedURIs)

        let sorted: [FeedItem]
        if feedOrder.isEmpty {
            sorted = all
        } else {
            sorted = all.sorted { a, b in
                let ai = feedOrder.firstIndex(of: a.id) ?? Int.max
                let bi = feedOrder.firstIndex(of: b.id) ?? Int.max
                return ai < bi
            }
        }

        visibleItems = sorted.filter { !hiddenURIs.contains($0.id) }
        hiddenItems  = sorted.filter {  hiddenURIs.contains($0.id) }
    }

    private func toggleVisibility(uri: String) {
        var hidden = settings.hiddenFeedURIs
        if hidden.contains(uri) {
            hidden.removeAll { $0 == uri }
        } else {
            hidden.append(uri)
        }
        settings.hiddenFeedURIs = hidden
        let all = visibleItems + hiddenItems
        buildItemLists(all: all)
    }

    #if targetEnvironment(macCatalyst)
    /// 表示フィードの index 番目の行を offset（-1 = 上, 1 = 下）だけ移動する
    private func moveItem(at index: Int, by offset: Int) {
        let target = index + offset
        guard visibleItems.indices.contains(target) else { return }
        withAnimation {
            visibleItems.swapAt(index, target)
        }
        saveOrder()
    }
    #endif

    private func saveOrder() {
        settings.pinnedFeedURIs = visibleItems.map { $0.id } + hiddenItems.map { $0.id }
    }
}
