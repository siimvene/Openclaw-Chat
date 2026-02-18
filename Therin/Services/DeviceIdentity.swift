import Foundation
import CryptoKit
import Security

/// Manages device identity (Ed25519 keypair) for OpenClaw gateway authentication.
/// Keypair is generated on first use and stored securely in Keychain.
class DeviceIdentity {
    static let shared = DeviceIdentity()
    
    private let privateKeyTag = "io.openclaw.device.privatekey"
    private let deviceTokenKey = "io.openclaw.device.token"
    private let installSentinelKey = "deviceIdentityInstalled"

    private var cachedPrivateKey: Curve25519.Signing.PrivateKey?

    private init() {
        clearKeychainIfReinstalled()
    }

    /// Clears stale Keychain entries when the app has been freshly installed.
    /// UserDefaults is wiped on delete but Keychain persists — detect the mismatch.
    private func clearKeychainIfReinstalled() {
        guard !UserDefaults.standard.bool(forKey: installSentinelKey) else { return }
        // Fresh install: wipe any leftover keypair and tokens from previous install
        let deleteQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        SecItemDelete(deleteQuery as CFDictionary)
        UserDefaults.standard.set(true, forKey: installSentinelKey)
        print("[DeviceIdentity] Fresh install detected — cleared stale Keychain entries")
    }
    
    /// Get or generate the device's Ed25519 private key
    var privateKey: Curve25519.Signing.PrivateKey {
        if let cached = cachedPrivateKey {
            return cached
        }
        
        if let loaded = loadPrivateKey() {
            cachedPrivateKey = loaded
            return loaded
        }
        
        let newKey = Curve25519.Signing.PrivateKey()
        savePrivateKey(newKey)
        cachedPrivateKey = newKey
        return newKey
    }
    
    /// Get the public key (base64url encoded, no padding)
    var publicKeyBase64: String {
        let publicKeyData = privateKey.publicKey.rawRepresentation
        return publicKeyData.base64URLEncodedString()
    }
    
    /// Get device ID (SHA256 hash of public key, hex encoded)
    var deviceId: String {
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let hash = SHA256.hash(data: publicKeyData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Sign the device auth payload for connect
    /// Payload format: v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
    func signPayload(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String,
        nonce: String
    ) -> String? {
        let payload = [
            "v2",
            deviceId,
            clientId,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            token,
            nonce
        ].joined(separator: "|")
        
        guard let payloadData = payload.data(using: .utf8) else { return nil }
        let signature = try? privateKey.signature(for: payloadData)
        return signature?.base64URLEncodedString()
    }
    
    /// Store device token received from gateway
    func storeDeviceToken(_ token: String, for gatewayHost: String) {
        let key = "\(deviceTokenKey).\(gatewayHost)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// Load device token for a gateway
    func loadDeviceToken(for gatewayHost: String) -> String? {
        let key = "\(deviceTokenKey).\(gatewayHost)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    /// Clear device token (e.g., on revocation)
    func clearDeviceToken(for gatewayHost: String) {
        let key = "\(deviceTokenKey).\(gatewayHost)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Private Key Storage
    
    private func savePrivateKey(_ key: Curve25519.Signing.PrivateKey) {
        let keyData = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: privateKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[DeviceIdentity] Failed to save private key: \(status)")
        }
    }
    
    private func loadPrivateKey() -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: privateKeyTag,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let keyData = result as? Data {
            return try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        }
        return nil
    }
}

// MARK: - Base64URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension Curve25519.Signing.PublicKey {
    var base64URLEncoded: String {
        rawRepresentation.base64URLEncodedString()
    }
}
