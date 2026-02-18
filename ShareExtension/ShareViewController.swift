import UIKit
import Social
import UniformTypeIdentifiers
import CryptoKit

class ShareViewController: UIViewController {
    
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressView = UIActivityIndicatorView(style: .large)
    private let cancelButton = UIButton(type: .system)
    
    private let appGroupId = "group.io.kleidia.clawchat"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedContent()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        
        containerView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        titleLabel.text = "Sending to OpenClaw"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)
        
        statusLabel.text = "Processing..."
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = UIColor(white: 0.7, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)
        
        progressView.color = .white
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.startAnimating()
        containerView.addSubview(progressView)
        
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .systemRed
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        containerView.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),
            containerView.heightAnchor.constraint(equalToConstant: 180),
            
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            progressView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            
            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor)
        ])
    }
    
    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0, userInfo: nil))
    }
    
    private func processSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            showError("No content to share")
            return
        }
        
        // Check if gateway is configured
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let gatewayURL = defaults.string(forKey: "gatewayURL"),
              let gatewayToken = defaults.string(forKey: "gatewayToken"),
              !gatewayURL.isEmpty, !gatewayToken.isEmpty else {
            showError("Please configure gateway in ClawChat app first")
            return
        }
        
        // Process attachments
        Task {
            do {
                var message = ""
                var imageData: Data?
                
                for attachment in attachments {
                    if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        statusLabel.text = "Processing image..."
                        imageData = try await loadImage(from: attachment)
                    } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        let url = try await loadURL(from: attachment)
                        message += url.absoluteString + "\n"
                    } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        let text = try await loadText(from: attachment)
                        message += text + "\n"
                    }
                }
                
                message = message.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if message.isEmpty && imageData == nil {
                    showError("No supported content found")
                    return
                }
                
                await MainActor.run {
                    statusLabel.text = "Sending to gateway..."
                }
                
                try await sendToGateway(
                    url: gatewayURL,
                    token: gatewayToken,
                    message: message.isEmpty ? "Shared image" : message,
                    imageData: imageData
                )
                
                await MainActor.run {
                    showSuccess()
                }
            } catch {
                await MainActor.run {
                    showError(error.localizedDescription)
                }
            }
        }
    }
    
    private func loadImage(from attachment: NSItemProvider) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                var imageData: Data?
                
                if let url = item as? URL {
                    imageData = try? Data(contentsOf: url)
                } else if let image = item as? UIImage {
                    imageData = image.jpegData(compressionQuality: 0.8)
                } else if let data = item as? Data {
                    imageData = data
                }
                
                if let data = imageData {
                    // Resize if too large (max 4MB)
                    if data.count > 4_000_000, let image = UIImage(data: data) {
                        let resized = self.resizeImage(image, maxSize: 1920)
                        if let resizedData = resized.jpegData(compressionQuality: 0.7) {
                            continuation.resume(returning: resizedData)
                            return
                        }
                    }
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load image"]))
                }
            }
        }
    }
    
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        if ratio >= 1 { return image }
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func loadURL(from attachment: NSItemProvider) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not load URL"]))
                }
            }
        }
    }
    
    private func loadText(from attachment: NSItemProvider) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not load text"]))
                }
            }
        }
    }
    
    private func sendToGateway(url: String, token: String, message: String, imageData: Data?) async throws {
        // Queue message in app group for main app to process
        // (Share extensions can't maintain WebSocket connections)
        if let defaults = UserDefaults(suiteName: appGroupId) {
            var pendingShares = defaults.array(forKey: "pendingShares") as? [[String: Any]] ?? []
            
            var shareItem: [String: Any] = [
                "message": message,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            if let imageData = imageData {
                // Save image to shared container
                let fileManager = FileManager.default
                if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
                    let imagesDir = containerURL.appendingPathComponent("SharedImages", isDirectory: true)
                    try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                    
                    let imageId = UUID().uuidString
                    let imageURL = imagesDir.appendingPathComponent("\(imageId).jpg")
                    try imageData.write(to: imageURL)
                    shareItem["imagePath"] = imageURL.path
                }
            }
            
            pendingShares.append(shareItem)
            defaults.set(pendingShares, forKey: "pendingShares")
        }
    }
    
    private func showSuccess() {
        progressView.stopAnimating()
        progressView.isHidden = true
        titleLabel.text = "Sent!"
        statusLabel.text = "Open ClawChat to continue the conversation"
        cancelButton.setTitle("Done", for: .normal)
        cancelButton.tintColor = .systemBlue
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
    
    private func showError(_ message: String) {
        progressView.stopAnimating()
        progressView.isHidden = true
        titleLabel.text = "Error"
        titleLabel.textColor = .systemRed
        statusLabel.text = message
        cancelButton.setTitle("Close", for: .normal)
    }
}
