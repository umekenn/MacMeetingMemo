import Foundation
import Vision
import AppKit

// MARK: - OCR Manager
// Vision framework を使って PNG/JPEG からテキストを認識する。
// macOS のプレビューアプリが使うのと同じ Apple ネイティブ OCR エンジン。
// 日本語・英語混在に対応。外部サービス不要。

struct OCRManager {

    /// 画像ファイルから OCR テキストを取得する（非同期）
    static func recognizeText(from imageURL: URL) async -> String? {
        guard let cgImage = loadCGImage(from: imageURL) else {
            print("[OCR] Failed to load image: \(imageURL.lastPathComponent)")
            return nil
        }
        return await recognizeText(from: cgImage)
    }

    /// CGImage から OCR テキストを取得する
    static func recognizeText(from cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error = error {
                    print("[OCR] Recognition error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }
                let result = lines.joined(separator: "\n")
                continuation.resume(returning: result.isEmpty ? nil : result)
            }

            // macOS のプレビューと同じ「正確優先」モード + 日本語・英語
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[OCR] Handler error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Private Helpers

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return image
    }
}
