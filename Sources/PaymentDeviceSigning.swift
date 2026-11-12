import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum PaymentDeviceSigning {
    enum SigningError: LocalizedError {
        case secureEnclaveUnavailable
        case invalidStoredKey
        case loginRequired

        var errorDescription: String? {
            switch self {
            case .secureEnclaveUnavailable:
                return "这台设备不支持安全区支付密钥"
            case .invalidStoredKey:
                return "支付安全密钥无效，请重新绑定设备"
            case .loginRequired:
                return "账号尚未登录"
            }
        }
    }

    private static let keyAccount = "xingyan.payment.enclave.p256.v1"
    private static let tokenAccount = "xingyan.payment.token.v1"
    private static let tokenDeviceAccount = "xingyan.payment.token.device.v1"

    static var deviceId: String { AppInfo.deviceId }
    static var secureHardwareAvailable: Bool { SecureEnclave.isAvailable }

    private static func publicKeyPEM() throws -> String {
        let key = try privateKey()
        let der = key.publicKey.derRepresentation
        let base64 = der.base64EncodedString(options: [
            .lineLength64Characters,
            .endLineWithLineFeed
        ])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----"
    }

    static func signCanonical(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let signature = try privateKey().signature(for: data)
        return signature.derRepresentation.base64EncodedString()
    }

    static func ensureEnrollment(userId: String) async throws -> PaymentDeviceRegistrationPayload {
        guard !userId.isEmpty else { throw SigningError.loginRequired }
        if let token = Keychain.get(tokenAccount),
           let boundDevice = Keychain.get(tokenDeviceAccount),
           boundDevice == deviceId {
            return PaymentDeviceRegistrationPayload(
                tokenId: token,
                deviceId: boundDevice,
                last4: nil,
                status: "active"
            )
        }
        let publicKey = try publicKeyPEM()
        let challenge = try await API.shared.paymentDeviceChallenge(
            deviceId: deviceId,
            publicKey: publicKey
        )
        let payload: [String: Any] = [
            "purpose": "payment-device-enrollment",
            "challenge": challenge.challenge,
            "tokenId": challenge.tokenId,
            "userId": userId,
            "deviceId": deviceId,
            "publicKey": publicKey
        ]
        let signature = try signCanonical(payload)
        let registration = try await API.shared.enrollPaymentDevice(
            challenge: challenge.challenge,
            signature: signature,
            last4: ""
        )
        Keychain.set(registration.tokenId, for: tokenAccount)
        Keychain.set(registration.deviceId, for: tokenDeviceAccount)
        return registration
    }

    static func clearLocalBinding() {
        Keychain.remove(tokenAccount)
        Keychain.remove(tokenDeviceAccount)
    }

    private static func privateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw SigningError.secureEnclaveUnavailable }
        if let encoded = Keychain.get(keyAccount),
           let data = Data(base64Encoded: encoded) {
            do { return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) }
            catch { throw SigningError.invalidStoredKey }
        }
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            &accessError
        ) else {
            throw SigningError.secureEnclaveUnavailable
        }
        let context = LAContext()
        context.localizedFallbackTitle = "输入支付密码"
        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(
                compactRepresentable: false,
                accessControl: access,
                authenticationContext: context
            )
        } catch {
            throw SigningError.secureEnclaveUnavailable
        }
        Keychain.set(key.dataRepresentation.base64EncodedString(), for: keyAccount)
        return key
    }
}
