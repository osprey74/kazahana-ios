// VideoPlayerView.swift
// kazahana-ios
// 動画再生ビュー（AVPlayer + HLS）

import SwiftUI
import AVKit

struct VideoPlayerView: View {

    let video: EmbedVideo
    /// true の場合はサムネイル表示のみで再生ボタンを無効化する（通知画面など）
    var thumbnailOnly: Bool = false
    @State private var player: AVPlayer? = nil
    @State private var isPresented: Bool = false

    private var hasAlt: Bool {
        if let alt = video.alt, !alt.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                // サムネイル
                thumbnailView
                    .overlay(alignment: .center) {
                        if !thumbnailOnly {
                            Button {
                                isPresented = true
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 52))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.4), radius: 6)
                            }
                        } else {
                            // サムネイルのみモード：再生不可を示すアイコン
                            Image(systemName: "play.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.6))
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if hasAlt {
                            Text("ALT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                                .padding(8)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // ALT テキスト本文（thumbnailOnly でないとき、先頭 128 文字まで表示）
            if !thumbnailOnly, let alt = video.alt, !alt.isEmpty {
                Text(alt.count > 128 ? String(alt.prefix(128)) + "…" : alt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fullScreenCover(isPresented: $isPresented, onDismiss: {
            player?.pause()
            player = nil
        }) {
            VideoPlayerSheet(playlistURL: video.playlist)
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumb = video.thumbnail, let url = URL(string: thumb) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Rectangle().fill(Color.secondary.opacity(0.2))
                    }
                }
            } else {
                Rectangle().fill(Color.secondary.opacity(0.2))
            }
        }
    }

    private var aspectRatio: CGFloat {
        guard let ar = video.aspectRatio, ar.height > 0 else { return 16 / 9 }
        return CGFloat(ar.width) / CGFloat(ar.height)
    }
}

// MARK: - フルスクリーン再生シート

private struct VideoPlayerSheet: View {

    let playlistURL: String?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(16)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            guard let urlString = playlistURL, let url = URL(string: urlString) else { return }
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
