// FeedSelectorView.swift
// kazahana-ios
// ホーム画面のフィード選択ドロワー

import SwiftUI

struct FeedSelectorView: View {
    let viewModel: TimelineViewModel
    @Binding var isPresented: Bool
    @Environment(AppSettings.self) private var settings

    /// 表示するフィードソース一覧
    /// showAllFeedsInSelector ON → 非表示設定のフィードも含め全件表示（Windows版準拠）
    /// showAllFeedsInSelector OFF → hiddenFeedURIs を除外して表示
    private var displayedSources: [FeedSource] {
        if settings.showAllFeedsInSelector {
            return viewModel.allFeedSources
        } else {
            let hiddenURIs = Set(settings.hiddenFeedURIs)
            return viewModel.allFeedSources.filter { source in
                guard let uri = source.uri else { return true }
                return !hiddenURIs.contains(uri)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // フォロー中フィード（常に表示）
                feedRow(for: .following)

                // カスタムフィード
                let customFeeds = displayedSources.filter { if case .custom = $0 { return true } else { return false } }
                if !customFeeds.isEmpty {
                    Section(String(localized: "feed.savedFeeds")) {
                        ForEach(customFeeds, id: \.self) { source in
                            feedRow(for: source)
                        }
                    }
                }

                // リスト
                let listFeeds = displayedSources.filter { if case .list = $0 { return true } else { return false } }
                if !listFeeds.isEmpty {
                    Section(String(localized: "feed.lists")) {
                        ForEach(listFeeds, id: \.self) { source in
                            feedRow(for: source)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "feed.selectFeed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) {
                        isPresented = false
                    }
                }
            }
            .task {
                if viewModel.savedFeeds.isEmpty && viewModel.savedLists.isEmpty {
                    await viewModel.loadSavedFeeds()
                }
            }
        }
    }

    @ViewBuilder
    private func feedRow(for feed: FeedSource) -> some View {
        let isSelected = viewModel.currentFeed == feed
        Button {
            Task {
                await viewModel.selectFeed(feed)
                isPresented = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: feed.icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Text(feed.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }
        }
        .listRowBackground(isSelected ? Color.blue.opacity(0.08) : nil)
    }
}
