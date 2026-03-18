import SwiftUI

private struct NotificationPostURI: Identifiable, Hashable {
    let uri: String
    var id: String { uri }
}

struct NotificationListView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var viewModel: NotificationViewModel?
    @State private var postService: PostService?
    @State private var selectedPostURI: NotificationPostURI?
    @State private var selectedAuthorDID: IdentifiableString?
    @State private var replyToPost: PostView? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    notificationContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            // スレッド遷移
            .navigationDestination(item: $selectedPostURI) { item in
                ThreadView(uri: item.uri, postService: PostService(client: authVM.client))
                    .environment(authVM)
            }
            // プロフィール遷移
            .navigationDestination(item: $selectedAuthorDID) { item in
                ProfileScreenView(actor: item.value)
                    .environment(authVM)
            }
            // 返信 ComposeView
            .sheet(item: $replyToPost) { replyTo in
                if let ps = postService {
                    ComposeView(postService: ps, replyTo: replyTo)
                }
            }
        }
        .task {
            setupViewModel()
            await viewModel?.loadInitial()
        }
    }

    /// 通知に対応する投稿 URI を返す（タップ遷移 & subjectPost 表示両用）
    private func notificationPostURI(_ notification: AppNotification, resolvedRepostURIs: [String: String]) -> String? {
        switch notification.reason {
        case "like", "repost":
            return notification.reasonSubject
        case "like-via-repost", "repost-via-repost":
            // repost レコード URI → 元投稿 URI に解決済みのものを使用
            return notification.reasonSubject.flatMap { resolvedRepostURIs[$0] }
        case "reply", "mention", "quote":
            return notification.uri
        default:
            return nil
        }
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        let notificationService = NotificationService(client: authVM.client)
        let ps = PostService(client: authVM.client)
        postService = ps
        viewModel = NotificationViewModel(notificationService: notificationService, postService: ps)
    }

    @ViewBuilder
    private func notificationContent(vm: NotificationViewModel) -> some View {
        if vm.isLoading && vm.notifications.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.notifications.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("再試行") {
                    Task { await vm.loadInitial() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } else if vm.notifications.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "bell.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("通知はありません")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.notifications) { notification in
                    // follow 通知はタップ不可（アバターのみプロフィールへ）
                    // それ以外は投稿URIがあればスレッドへ遷移
                    let postURI = notificationPostURI(notification, resolvedRepostURIs: vm.resolvedRepostURIs)
                    let subjectPost = postURI.flatMap { vm.subjectPosts[$0] }

                    NotificationItemView(
                        notification: notification,
                        subjectPost: subjectPost,
                        postService: postService,
                        onTapAuthor: { did in
                            selectedAuthorDID = IdentifiableString(did)
                        },
                        onTapReply: { post in
                            replyToPost = post
                        }
                    )
                    // 投稿本体エリアタップ → スレッド遷移（アクションバーボタンは優先）
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let uri = postURI {
                            selectedPostURI = NotificationPostURI(uri: uri)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .task {
                        if notification.id == vm.notifications.last?.id {
                            await vm.loadMore()
                        }
                    }
                }
                if vm.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await vm.refresh()
            }
        }
    }
}
