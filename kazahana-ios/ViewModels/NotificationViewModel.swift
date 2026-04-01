import Foundation
import Observation

@Observable
final class NotificationViewModel {
    var notifications: [AppNotification] = []
    /// URI → PostView のキャッシュ（いいね・リポスト対象投稿など）
    var subjectPosts: [String: PostView] = [:]
    /// repost URI → 元投稿 URI の解決済みマップ
    var resolvedRepostURIs: [String: String] = [:]
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var unreadCount = 0

    /// 同一投稿への同種アクション（like/repost等）をグループ化した通知リスト
    var groupedNotifications: [NotificationGroup] {
        var groups: [NotificationGroup] = []
        var groupIndexMap: [String: Int] = [:]

        for notif in notifications {
            // like/repost系のみグループ化。reply/mention/quote/followは個別表示
            let groupKey: String?
            switch notif.reason {
            case "like", "repost", "like-via-repost", "repost-via-repost":
                if let subject = notif.reasonSubject {
                    groupKey = "\(notif.reason):\(subject)"
                } else {
                    groupKey = nil
                }
            default:
                groupKey = nil
            }

            if let key = groupKey, let idx = groupIndexMap[key] {
                let existing = groups[idx]
                groups[idx] = NotificationGroup(
                    id: existing.id,
                    reason: existing.reason,
                    reasonSubject: existing.reasonSubject,
                    notifications: existing.notifications + [notif]
                )
            } else {
                let newID = groupKey ?? notif.uri
                let group = NotificationGroup(
                    id: newID,
                    reason: notif.reason,
                    reasonSubject: notif.reasonSubject,
                    notifications: [notif]
                )
                groupIndexMap[newID] = groups.count
                groups.append(group)
            }
        }
        return groups
    }

    private var cursor: String?
    private var hasMore = true
    private let notificationService: NotificationService
    private let postService: PostService?

    init(notificationService: NotificationService, postService: PostService? = nil) {
        self.notificationService = notificationService
        self.postService = postService
    }

    @MainActor
    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await notificationService.listNotifications(limit: 50)
            notifications = response.notifications
            cursor = response.cursor
            hasMore = response.cursor != nil
            await markAsSeen()
            await fetchSubjectPosts(for: response.notifications)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        cursor = nil
        hasMore = true

        do {
            let response = try await notificationService.listNotifications(limit: 50)
            notifications = response.notifications
            cursor = response.cursor
            hasMore = response.cursor != nil
            await markAsSeen()
            subjectPosts = [:]
            resolvedRepostURIs = [:]
            await fetchSubjectPosts(for: response.notifications)
        } catch {
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    @MainActor
    func loadMore() async {
        guard !isLoading, hasMore, let currentCursor = cursor else { return }
        isLoading = true

        do {
            let response = try await notificationService.listNotifications(limit: 50, cursor: currentCursor)
            notifications.append(contentsOf: response.notifications)
            cursor = response.cursor
            hasMore = response.cursor != nil
            await fetchSubjectPosts(for: response.notifications)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - subject投稿取得

    @MainActor
    private func fetchSubjectPosts(for notifs: [AppNotification]) async {
        guard let postService else { return }

        // Step1: like-via-repost / repost-via-repost のリポストレコードを解決して元投稿 URI を取得
        var viaRepostNotifs = notifs.filter { $0.isViaRepost && $0.reasonSubject != nil }
        viaRepostNotifs = viaRepostNotifs.filter { notif in
            // reasonSubject のリポスト URI がまだ解決されていないもののみ
            guard let repostURI = notif.reasonSubject else { return false }
            return resolvedRepostURIs[repostURI] == nil
        }

        for notif in viaRepostNotifs {
            guard let repostURI = notif.reasonSubject else { continue }
            if let postURI = await resolveRepostURI(repostURI) {
                resolvedRepostURIs[repostURI] = postURI
            }
        }

        // Step2: 通知に対応する投稿 URI を収集
        var uris: [String] = []
        for notif in notifs {
            let uri: String?
            switch notif.reason {
            case "like", "repost":
                uri = notif.reasonSubject
            case "like-via-repost", "repost-via-repost":
                // repost URI → 元投稿 URI に解決済みのものを使用
                uri = notif.reasonSubject.flatMap { resolvedRepostURIs[$0] }
            case "reply", "mention", "quote":
                uri = notif.uri
            default:
                uri = nil
            }
            if let uri, subjectPosts[uri] == nil {
                uris.append(uri)
            }
        }

        // 重複除去
        let unique = Array(Set(uris))
        guard !unique.isEmpty else { return }

        // app.bsky.feed.getPosts は最大25件なので25件ずつバッチ処理
        let batchSize = 25
        var index = 0
        while index < unique.count {
            let batch = Array(unique[index..<min(index + batchSize, unique.count)])
            index += batchSize
            do {
                let posts = try await postService.getPosts(uris: batch)
                for post in posts {
                    subjectPosts[post.uri] = post
                }
            } catch {
                print("[NotificationVM] fetchSubjectPosts error: \(error)")
            }
        }
    }

    /// repost レコード URI（at://did/app.bsky.feed.repost/rkey）から元投稿 URI を解決する
    private func resolveRepostURI(_ repostURI: String) async -> String? {
        guard let postService else { return nil }
        // at://did/app.bsky.feed.repost/rkey を解析
        let pattern = #"^at://([^/]+)/app\.bsky\.feed\.repost/(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: repostURI, range: NSRange(repostURI.startIndex..., in: repostURI)),
              let repoRange = Range(match.range(at: 1), in: repostURI),
              let rkeyRange = Range(match.range(at: 2), in: repostURI) else {
            return nil
        }
        let repo = String(repostURI[repoRange])
        let rkey = String(repostURI[rkeyRange])

        do {
            let record = try await postService.getRecord(
                repo: repo,
                collection: "app.bsky.feed.repost",
                rkey: rkey
            )
            return record.value?.subject?.uri
        } catch {
            print("[NotificationVM] resolveRepostURI error: \(error)")
            return nil
        }
    }

    @MainActor
    func fetchUnreadCount() async {
        do {
            unreadCount = try await notificationService.getUnreadCount()
        } catch {
            // Silently fail for badge count
        }
    }

    @MainActor
    private func markAsSeen() async {
        try? await notificationService.updateSeen()
        unreadCount = 0
    }
}
