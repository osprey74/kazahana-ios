// ClaudeService.swift
// kazahana-ios
// Claude API を使った画像 ALT テキスト自動生成

import UIKit

struct ClaudeService {

    // MARK: - モデル設定
    private static let model = "claude-haiku-4-5-20251001"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let maxTokens = 300

    // MARK: - ALT テキスト生成

    /// 画像から ALT テキストを生成する
    /// - Parameters:
    ///   - image: 対象の UIImage
    ///   - apiKey: Anthropic API キー
    ///   - languageCode: 言語コード（例: "ja", "en"）
    /// - Returns: 生成された ALT テキスト
    static func generateAltText(for image: UIImage, apiKey: String, languageCode: String = "ja") async throws -> String {
        // 画像を JPEG base64 に変換（最大 1MB に圧縮）
        guard let base64 = imageToBase64(image) else {
            throw ClaudeError.imageConversionFailed
        }

        // BCP-47 言語コードを自然言語名に変換（Claude が認識しやすい形式）
        let languageName: String
        switch languageCode {
        case "ja": languageName = "Japanese"
        case "en": languageName = "English"
        case "zh": languageName = "Chinese"
        case "ko": languageName = "Korean"
        case "fr": languageName = "French"
        case "de": languageName = "German"
        case "es": languageName = "Spanish"
        case "pt": languageName = "Portuguese"
        default:   languageName = languageCode
        }

        let prompt = "Generate a concise accessibility ALT text for this image in \(languageName). Describe what is shown in the image specifically, within 150 characters. Output only the ALT text itself with no preamble or explanation."

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeError.unexpectedResponseFormat
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private helpers

    /// UIImage を JPEG base64 文字列に変換（1MB 以下になるよう圧縮）
    private static func imageToBase64(_ image: UIImage) -> String? {
        let maxBytes = 1_000_000

        // 最大幅 1024px に縮小（API 用なので高解像度不要）
        let maxWidthPx: CGFloat = 1024
        let pixelWidth  = image.size.width  * image.scale
        let pixelHeight = image.size.height * image.scale
        let scale = min(1.0, maxWidthPx / pixelWidth)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0

        let drawSize = CGSize(
            width:  round(pixelWidth  * scale),
            height: round(pixelHeight * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: drawSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: drawSize))
        }

        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data.base64EncodedString()
            }
            quality -= 0.1
        }
        // フォールバック
        return resized.jpegData(compressionQuality: 0.2)?.base64EncodedString()
    }
}

// MARK: - エラー型

enum ClaudeError: LocalizedError {
    case imageConversionFailed
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case unexpectedResponseFormat

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "画像の変換に失敗しました"
        case .invalidResponse:
            return "無効なレスポンスを受信しました"
        case .apiError(let statusCode, let message):
            if statusCode == 401 {
                return "APIキーが無効です。設定を確認してください"
            }
            return "APIエラー (\(statusCode)): \(message)"
        case .unexpectedResponseFormat:
            return "予期しないレスポンス形式です"
        }
    }
}
