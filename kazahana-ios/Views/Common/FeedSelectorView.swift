// FeedSelectorView.swift
// kazahana-ios
// ホーム画面のフィード選択ドロワー

import SwiftUI

struct FeedSelectorView: View {
    let viewModel: TimelineViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                // フォロー中フィード
                feedRow(for: .following)

                // カスタムフィード
                if !viewModel.savedFeeds.isEmpty {
                    Section("保存済みフィード") {
                        ForEach(viewModel.savedFeeds) { generator in
                            feedRow(for: .custom(generator))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("フィードを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
            .task {
                if viewModel.savedFeeds.isEmpty {
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
