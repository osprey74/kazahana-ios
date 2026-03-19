// ContentView.swift
// kazahana-ios
// ルートビュー（認証状態によりログイン画面 or メイン画面を切り替え）

import SwiftUI

struct ContentView: View {

    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        if authVM.isLoggedIn {
            MainTabView(client: authVM.client)
        } else {
            LoginView()
        }
    }
}

// MARK: - メインタブ画面

struct MainTabView: View {

    @Environment(AuthViewModel.self) private var authVM
    let client: ATProtoClient
    @State private var selectedTab: Tab = .home
    @State private var dmUnreadCount = 0

    enum Tab {
        case home, search, notifications, messages, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(client: client)
                .tabItem {
                    Label(String(localized: "tab.home"), systemImage: "house")
                }
                .tag(Tab.home)

            SearchView()
                .tabItem {
                    Label(String(localized: "tab.search"), systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            NotificationListView()
                .tabItem {
                    Label(String(localized: "tab.notifications"), systemImage: "bell")
                }
                .tag(Tab.notifications)

            ConversationListView(onUnreadCountChanged: { count in
                dmUnreadCount = count
            })
                .tabItem {
                    Label(String(localized: "tab.messages"), systemImage: "envelope")
                }
                .badge(dmUnreadCount > 0 ? dmUnreadCount : 0)
                .tag(Tab.messages)

            // 自分のプロフィール
            selfProfileView
                .tabItem {
                    Label(String(localized: "tab.profile"), systemImage: "person.circle")
                }
                .tag(Tab.profile)
        }
    }

    @ViewBuilder
    private var selfProfileView: some View {
        if let did = client.currentSession?.did {
            NavigationStack {
                ProfileScreenView(actor: did)
                    .navigationTitle(String(localized: "tab.profile"))
            }
        } else {
            PlaceholderView(title: String(localized: "tab.profile"), icon: "person.circle")
        }
    }
}

// MARK: - プレースホルダー（Phase 4以降に置き換え）

struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(String(localized: "dm.comingSoon"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

#Preview {
    ContentView()
        .environment(AuthViewModel())
}
