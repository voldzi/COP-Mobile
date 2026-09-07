import SwiftUI
import UIKit

@MainActor
enum CSMAvatarImage {
    private static let cache = NSCache<NSString, UIImage>()

    static func uiImage(from dataURL: String?) -> UIImage? {
        guard let dataURL = normalizedDataURL(dataURL) else { return nil }
        let cacheKey = dataURL as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let payload = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: payload), data.count <= OperatorProfilePreferences.maxAvatarDataURLLength,
              let image = UIImage(data: data)
        else {
            return nil
        }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    static func remoteURL(from value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              normalizedDataURL(trimmed) == nil,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https"
        else {
            return nil
        }
        return url
    }

    static func makeAvatarDataURL(from payload: Data) throws -> String {
        guard let image = UIImage(data: payload) else {
            throw AvatarImageError.unsupportedImage
        }

        let avatar = cropAndRenderAvatar(image)
        for quality in stride(from: 0.86, through: 0.42, by: -0.08) {
            guard let data = avatar.jpegData(compressionQuality: quality) else { continue }
            let value = "data:image/jpeg;base64,\(data.base64EncodedString())"
            if value.count <= OperatorProfilePreferences.maxAvatarDataURLLength {
                return value
            }
        }
        throw AvatarImageError.tooLarge
    }

    private static func normalizedDataURL(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= OperatorProfilePreferences.maxAvatarDataURLLength,
              trimmed.range(
                of: #"^data:image/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$"#,
                options: .regularExpression
              ) != nil
        else {
            return nil
        }
        return trimmed
    }

    private static func cropAndRenderAvatar(_ image: UIImage, targetSize: CGFloat = 256) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSize, height: targetSize))
        return renderer.image { _ in
            let sourceSize = image.size
            let side = min(sourceSize.width, sourceSize.height)
            let sourceRect = CGRect(
                x: max(0, (sourceSize.width - side) / 2),
                y: max(0, (sourceSize.height - side) / 2),
                width: side,
                height: side
            )
            if let cgImage = image.cgImage?.cropping(to: CGRect(
                x: sourceRect.origin.x * image.scale,
                y: sourceRect.origin.y * image.scale,
                width: sourceRect.width * image.scale,
                height: sourceRect.height * image.scale
            )) {
                UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
                    .draw(in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
            } else {
                image.draw(in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
            }
        }
    }
}

struct CSMAvatarImageView<Placeholder: View>: View {
    var dataUrl: String?
    var remoteUrl: String?
    var size: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        Group {
            if let image = CSMAvatarImage.uiImage(from: dataUrl) ?? CSMAvatarImage.uiImage(from: remoteUrl) {
                avatarImage(Image(uiImage: image))
            } else if let url = CSMAvatarImage.remoteURL(from: remoteUrl) {
                AsyncImage(url: url, transaction: Transaction(animation: .smooth)) { phase in
                    if let image = phase.image {
                        avatarImage(image)
                    } else {
                        placeholder()
                    }
                }
            } else {
                placeholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func avatarImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
    }
}

enum AvatarImageError: LocalizedError {
    case unsupportedImage
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            CSMLocalization.text("settings.account.avatar.unsupported", fallback: "Avatar musí být obrázek PNG, JPG nebo WebP.")
        case .tooLarge:
            CSMLocalization.text("settings.account.avatar.too_large", fallback: "Avatar je po zmenšení stále příliš velký.")
        }
    }
}
