// ReportView.swift
// kazahana-ios
// 投稿・アカウント通報画面

import SwiftUI

enum ReportTarget: Identifiable {
    case post(uri: String, cid: String)
    case account(did: String)

    var id: String {
        switch self {
        case .post(let uri, _): return "post:\(uri)"
        case .account(let did): return "account:\(did)"
        }
    }

    var title: String {
        switch self {
        case .post: return String(localized: "report.post")
        case .account: return String(localized: "report.account")
        }
    }
}

struct ReportView: View {

    let target: ReportTarget
    let postService: PostService

    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: ReportReasonType = .spam
    @State private var additionalComment: String = ""
    @State private var isSending = false
    @State private var errorMessage: String? = nil
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "report.reason")) {
                    ForEach(ReportReasonType.allCases) { reason in
                        reasonRow(reason)
                    }
                }

                Section(String(localized: "report.comment")) {
                    TextField(String(localized: "report.placeholder"), text: $additionalComment, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "report.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "report.submit")) {
                        Task { await sendReport() }
                    }
                    .disabled(isSending)
                }
            }
            .overlay {
                if isSending {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .alert(String(localized: "report.success"), isPresented: $didSend) {
                Button(String(localized: "report.close")) { dismiss() }
            } message: {
                Text(String(localized: "report.thanks"))
            }
        }
    }

    @ViewBuilder
    private func reasonRow(_ reason: ReportReasonType) -> some View {
        Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedReason == reason {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sendReport() async {
        isSending = true
        errorMessage = nil
        let comment = additionalComment.isEmpty ? nil : additionalComment
        do {
            switch target {
            case .post(let uri, let cid):
                try await postService.reportPost(uri: uri, cid: cid, reasonType: selectedReason, reason: comment)
            case .account(let did):
                try await postService.reportAccount(did: did, reasonType: selectedReason, reason: comment)
            }
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
