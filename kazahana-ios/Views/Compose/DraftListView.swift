// DraftListView.swift
// kazahana-ios
// 下書き一覧シート

import SwiftUI

struct DraftListView: View {

    @Environment(\.dismiss) private var dismiss

    /// 下書きを選択したときのコールバック
    let onSelect: (PostDraft) -> Void

    @State private var drafts: [PostDraft] = []
    @State private var showDeleteAllAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView(
                        String(localized: "compose.draft.empty"),
                        systemImage: "doc.text"
                    )
                } else {
                    List {
                        ForEach(drafts) { draft in
                            Button {
                                onSelect(draft)
                                dismiss()
                            } label: {
                                draftRow(draft)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                DraftService.shared.delete(id: drafts[i].id)
                            }
                            drafts.remove(atOffsets: offsets)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "compose.draft.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                if !drafts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "compose.draft.deleteAll")) {
                            showDeleteAllAlert = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .alert(String(localized: "compose.draft.deleteAllConfirm"), isPresented: $showDeleteAllAlert) {
                Button(String(localized: "compose.draft.deleteAll"), role: .destructive) {
                    DraftService.shared.deleteAll()
                    drafts = []
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
        }
        .onAppear {
            drafts = DraftService.shared.loadAll()
        }
    }

    @ViewBuilder
    private func draftRow(_ draft: PostDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // テキストプレビュー（最大2行）
            if !draft.text.isEmpty {
                Text(draft.text)
                    .lineLimit(2)
                    .font(.body)
                    .foregroundStyle(.primary)
            } else {
                Text(String(localized: "compose.draft.noText"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            HStack(spacing: 8) {
                // 日時
                Text(RelativeDateTimeFormatter().localizedString(for: draft.createdAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 画像枚数
                if !draft.images.isEmpty {
                    Label("\(draft.images.count)", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 動画あり
                if draft.video != nil {
                    Label(String(localized: "compose.draft.hasVideo"), systemImage: "video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
