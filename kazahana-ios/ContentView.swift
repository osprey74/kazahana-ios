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

    enum Tab {
        case home, search, notifications, messages, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(client: client)
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }
                .tag(Tab.home)

            SearchView()
                .tabItem {
                    Label("検索", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            NotificationListView()
                .tabItem {
                    Label("通知", systemImage: "bell")
                }
                .tag(Tab.notifications)

            // Phase 4 で DM 実装
            PlaceholderView(title: "メッセージ", icon: "envelope")
                .tabItem {
                    Label("メッセージ", systemImage: "envelope")
                }
                .tag(Tab.messages)

            // 自分のプロフィール
            selfProfileView
                .tabItem {
                    Label("プロフィール", systemImage: "person.circle")
                }
                .tag(Tab.profile)
        }
    }

    @ViewBuilder
    private var selfProfileView: some View {
        if let did = client.currentSession?.did {
            NavigationStack {
                ProfileScreenView(actor: did)
                    .navigationTitle("プロフィール")
            }
        } else {
            PlaceholderView(title: "プロフィール", icon: "person.circle")
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
            Text("Phase 4 以降で実装予定")
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
