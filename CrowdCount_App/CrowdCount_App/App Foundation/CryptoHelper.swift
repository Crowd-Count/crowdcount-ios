import Foundation
import CryptoKit

// MARK: - Request Signing (HMAC-SHA256)
enum CryptoHelper {
    // In-memory signing key cache: "deviceId:password" -> SymmetricKey
    private static var signingKeyCache: [String: SymmetricKey] = [:]

    /// Derive signing key: SHA256(device_id + ":" + password)
    static func deriveSigningKey(deviceId: String, password: String) -> SymmetricKey {
        let cacheKey = "\(deviceId):\(password)"
        if let cached = signingKeyCache[cacheKey] {
            return cached
        }

        let keyData = SHA256.hash(data: Data(cacheKey.utf8))
        let key = SymmetricKey(data: keyData)
        signingKeyCache[cacheKey] = key
        return key
    }

    /// Compute SHA256 hex string of input
    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Sign a request and return signature headers
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - password: Device password
    ///   - method: HTTP method (e.g. "POST")
    ///   - path: URL path (e.g. "/check_password")
    ///   - body: Request body string (empty string if no body)
    /// - Returns: Dictionary of signature headers
    static func signRequest(
        deviceId: String,
        password: String,
        method: String,
        path: String,
        body: String
    ) -> [String: String] {
        let signingKey = deriveSigningKey(deviceId: deviceId, password: password)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        let bodyHash = sha256Hex(body)

        let stringToSign = "\(method)\n\(path)\n\(bodyHash)\n\(timestamp)\n\(nonce)"
        let signatureData = Data(stringToSign.utf8)

        let signature = HMAC<SHA256>.authenticationCode(for: signatureData, using: signingKey)
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()

        return [
            "X-CC-Signature": signatureHex,
            "X-CC-Timestamp": timestamp,
            "X-CC-Nonce": nonce,
            "X-CC-Device-Id": deviceId,
            "X-CC-Sig-Version": "1",
        ]
    }

    /// Generate a unique idempotency key
    static func generateIdempotencyKey() -> String {
        UUID().uuidString
    }
}
