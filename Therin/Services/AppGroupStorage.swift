import Foundation

/// Manages shared storage between main app and extensions via App Group
class AppGroupStorage {
    static let shared = AppGroupStorage()
    
    private let appGroupId = "group.io.kleidia.clawchat"
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }
    
    private init() {}
    
    // MARK: - Gateway Credentials
    
    var gatewayURL: String? {
        get { sharedDefaults?.string(forKey: "gatewayURL") }
        set { sharedDefaults?.set(newValue, forKey: "gatewayURL") }
    }
    
    var gatewayToken: String? {
        get { sharedDefaults?.string(forKey: "gatewayToken") }
        set { sharedDefaults?.set(newValue, forKey: "gatewayToken") }
    }
    
    /// Sync credentials from standard UserDefaults to App Group
    func syncCredentials() {
        let standardDefaults = UserDefaults.standard
        if let url = standardDefaults.string(forKey: "gatewayURL") {
            gatewayURL = url
        }
        if let token = standardDefaults.string(forKey: "gatewayToken") {
            gatewayToken = token
        }
    }
    
    // MARK: - Pending Shares
    
    struct PendingShare: Codable {
        let message: String
        let imagePath: String?
        let timestamp: TimeInterval
    }
    
    /// Get pending shares from extension
    func getPendingShares() -> [PendingShare] {
        guard let data = sharedDefaults?.array(forKey: "pendingShares") as? [[String: Any]] else {
            return []
        }
        
        return data.compactMap { dict in
            guard let message = dict["message"] as? String,
                  let timestamp = dict["timestamp"] as? TimeInterval else {
                return nil
            }
            return PendingShare(
                message: message,
                imagePath: dict["imagePath"] as? String,
                timestamp: timestamp
            )
        }
    }
    
    /// Clear pending shares after processing
    func clearPendingShares() {
        sharedDefaults?.removeObject(forKey: "pendingShares")
        
        // Clean up shared images
        let fileManager = FileManager.default
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let imagesDir = containerURL.appendingPathComponent("SharedImages", isDirectory: true)
            try? fileManager.removeItem(at: imagesDir)
        }
    }
    
    /// Load image data from shared path
    func loadSharedImage(at path: String) -> Data? {
        return FileManager.default.contents(atPath: path)
    }
}
