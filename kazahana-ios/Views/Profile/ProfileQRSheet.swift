// ProfileQRSheet.swift
// kazahana-ios
// プロフィール QR コード表示シート

import SwiftUI
import CoreImage.CIFilterBuiltins
import Photos

struct ProfileQRSheet: View {
    let handle: String
    let displayName: String
    @Environment(\.dismiss) private var dismiss

    @State private var toastMessage: String?

    private var profileURL: String {
        "https://bsky.app/profile/\(handle)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                qrCard
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                VStack(spacing: 12) {
                    actionButton(
                        title: String(localized: "profileQR.copyLink"),
                        icon: "doc.on.doc",
                        action: copyLink
                    )
                    actionButton(
                        title: String(localized: "profileQR.share"),
                        icon: "square.and.arrow.up",
                        action: shareLink
                    )
                    actionButton(
                        title: String(localized: "profileQR.save"),
                        icon: "arrow.down.to.line",
                        action: saveQRCode
                    )
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle(String(localized: "profileQR.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = toastMessage {
                    Text(msg)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toastMessage)
        }
    }

    // MARK: - QR Card

    @ViewBuilder
    private var qrCard: some View {
        VStack(spacing: 16) {
            if let qrImage = generateQRCode(from: profileURL) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }

            Text(displayName)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)

            Text("@\(handle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("Bluesky")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    /// 保存用カード画像をレンダリング
    private var saveCardView: some View {
        VStack(spacing: 16) {
            if let qrImage = generateQRCode(from: profileURL) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            }

            Text(displayName)
                .font(.headline)
                .fontWeight(.bold)

            Text("@\(handle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Bluesky")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(32)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - QR Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Actions

    private func copyLink() {
        UIPasteboard.general.string = profileURL
        showToast(String(localized: "profileQR.copiedToast"))
    }

    private func shareLink() {
        guard let url = URL(string: profileURL) else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var presenter = root
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            av.popoverPresentationController?.sourceView = presenter.view
            presenter.present(av, animated: true)
        }
    }

    @MainActor
    private func saveQRCode() {
        let renderer = ImageRenderer(content: saveCardView)
        renderer.scale = 3 // 高解像度
        guard let image = renderer.uiImage else {
            showToast(String(localized: "profileQR.saveError"))
            return
        }

        #if targetEnvironment(macCatalyst)
        saveToFile(image: image)
        #else
        saveToPhotoLibrary(image: image)
        #endif
    }

    // MARK: - Save (iOS)

    #if !targetEnvironment(macCatalyst)
    private func saveToPhotoLibrary(image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    showToast(String(localized: "profileQR.saveError"))
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                showToast(String(localized: "profileQR.savedToast"))
            }
        }
    }
    #endif

    // MARK: - Save (macOS Catalyst)

    #if targetEnvironment(macCatalyst)
    private func saveToFile(image: UIImage) {
        guard let pngData = image.pngData() else {
            showToast(String(localized: "profileQR.saveError"))
            return
        }

        let fileName = "kazahana-qr-\(handle).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pngData.write(to: tempURL)
        } catch {
            showToast(String(localized: "profileQR.saveError"))
            return
        }

        let picker = UIDocumentPickerViewController(forExporting: [tempURL])
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var presenter = root
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(picker, animated: true)
        }
    }
    #endif

    // MARK: - UI Helpers

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toastMessage = nil }
        }
    }
}
