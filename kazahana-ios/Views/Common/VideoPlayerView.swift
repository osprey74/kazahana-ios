// VideoPlayerView.swift
// kazahana-ios
// 動画再生ビュー（AVPlayer + HLS）

import SwiftUI
import AVKit

struct VideoPlayerView: View {

    let video: EmbedVideo
    @State private var player: AVPlayer? = nil
    @State private var isPresented: Bool = false

    var body: some View {
        ZStack {
            // サムネイル
            thumbnailView
                .overlay(alignment: .center) {
                    Button {
                        isPresented = true
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.4), radius: 6)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
