import CryptoKit
import Foundation

enum E2EEProtocolError: LocalizedError {
    case invalidKey(String)
    case invalidSignature
    case missingSignedPreKey
    case missingOneTimePreKey
    case invalidEnvelope
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidKey(let name): return "E2EE key is invalid: \(name)"
        case .invalidSignature: return "E2EE signed prekey verification failed"
        case .missingSignedPreKey: return "E2EE signed prekey is missing"
        case .missingOneTimePreKey: return "E2EE one-time prekey is missing"
        case .invalidEnvelope: return "E2EE envelope is invalid"
        case .authenticationFailed: return "E2EE message authentication failed"
        }
    }
}

struct E2EEPublicPreKey: Codable, Hashable {
    var id: Int
    var publicKey: String
}

struct E2EESignedPublicPreKey: Codable, Hashable {
    var id: Int
    var publicKey: String
    var signature: String
}

struct E2EEDeviceRegistration: Codable, Hashable {
    var protocolVersion: Int
    var deviceId: String
    var identityKey: String
    var signingKey: String
    var signedPreKey: E2EESignedPublicPreKey
    var oneTimePreKeys: [E2EEPublicPreKey]
}

struct E2EEPrivatePreKey: Codable, Hashable {
    var id: Int
    var privateKey: String
}

struct E2EEPrivateSignedPreKey: Codable, Hashable {
    var id: Int
    var privateKey: String
    var signature: String
}

struct E2EEDevicePrivateState: Codable, Hashable {
    var protocolVersion: Int
    var deviceId: String
    var identityPrivateKey: String
    var signingPrivateKey: String
    var signedPreKey: E2EEPrivateSignedPreKey
    var oneTimePreKeys: [E2EEPrivatePreKey]
    var nextPreKeyId: Int
    var createdAt: String
}

struct E2EESessionState: Codable, Hashable {
    var protocolVersion: Int
    var sessionId: String
    var rootKey: Data
    var sendChainKey: Data
    var receiveChainKey: Data
    var sendCounter: Int
    var receiveCounter: Int
}

struct E2EEMessageEnvelope: Codable, Hashable {
    var version: Int
    var sessionId: String
    var messageId: String
    var senderUserId: String
    var senderDeviceId: String
    var senderIdentityKey: String
    var recipientUserId: String
    var recipientDeviceId: String
    var ephemeralKey: String
    var signedPreKeyId: Int
    var oneTimePreKeyId: Int?
    var nonce: String
    var ciphertext: String
    var createdAt: String
}

enum E2EEFoundationConfig {
    /// Dormant until the server prekey directory, device verification and
    /// encrypted-media path have passed end-to-end rollout gates.
    static let enabled = false
    static let protocolVersion = 1
}

enum E2EEProtocol {
    static let signedPreKeyDomain = Data("xingyan-e2ee-spk-v1".utf8)

    static func generateDeviceState(
        deviceId: String,
        signedPreKeyId: Int = 1,
        oneTimePreKeyStart: Int = 1,
        oneTimePreKeyCount: Int = 50
    ) throws -> E2EEDevicePrivateState {
        let identity = Curve25519.KeyAgreement.PrivateKey()
        let signing = Curve25519.Signing.PrivateKey()
        let signedPreKey = Curve25519.KeyAgreement.PrivateKey()
        let signature = try signing.signature(
            for: signedPreKeyDomain + signedPreKey.publicKey.rawRepresentation
        )
        let count = max(0, min(200, oneTimePreKeyCount))
        let oneTimePreKeys = (0..<count).map { index in
            let key = Curve25519.KeyAgreement.PrivateKey()
            return E2EEPrivatePreKey(
                id: oneTimePreKeyStart + index,
                privateKey: base64URL(key.rawRepresentation)
            )
        }
        return E2EEDevicePrivateState(
            protocolVersion: E2EEFoundationConfig.protocolVersion,
            deviceId: deviceId,
            identityPrivateKey: base64URL(identity.rawRepresentation),
            signingPrivateKey: base64URL(signing.rawRepresentation),
            signedPreKey: E2EEPrivateSignedPreKey(
                id: signedPreKeyId,
                privateKey: base64URL(signedPreKey.rawRepresentation),
                signature: base64URL(signature)
            ),
            oneTimePreKeys: oneTimePreKeys,
            nextPreKeyId: oneTimePreKeyStart + count,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    static func publicRegistration(
        for state: E2EEDevicePrivateState
    ) throws -> E2EEDeviceRegistration {
        let identity = try agreementPrivate(state.identityPrivateKey, name: "identity")
        let signing = try signingPrivate(state.signingPrivateKey)
        let signedPreKey = try agreementPrivate(
            state.signedPreKey.privateKey,
            name: "signed-prekey"
        )
        let oneTimePreKeys = try state.oneTimePreKeys.map { row in
            let key = try agreementPrivate(row.privateKey, name: "one-time-prekey")
            return E2EEPublicPreKey(
                id: row.id,
                publicKey: base64URL(key.publicKey.rawRepresentation)
            )
        }
        return E2EEDeviceRegistration(
            protocolVersion: E2EEFoundationConfig.protocolVersion,
            deviceId: state.deviceId,
            identityKey: base64URL(identity.publicKey.rawRepresentation),
            signingKey: base64URL(signing.publicKey.rawRepresentation),
            signedPreKey: E2EESignedPublicPreKey(
                id: state.signedPreKey.id,
                publicKey: base64URL(signedPreKey.publicKey.rawRepresentation),
                signature: state.signedPreKey.signature
            ),
            oneTimePreKeys: oneTimePreKeys
        )
    }

    static func verifySignedPreKey(
        device: E2EEDeviceRegistration
    ) throws {
        let signing = try signingPublic(device.signingKey)
        guard let signature = data(base64URL: device.signedPreKey.signature),
              let signedPreKey = data(base64URL: device.signedPreKey.publicKey),
              signing.isValidSignature(signature, for: signedPreKeyDomain + signedPreKey) else {
            throw E2EEProtocolError.invalidSignature
        }
    }

    static func startInitiatorSession(
        initiatorUserId: String,
        initiatorDeviceId: String,
        recipientUserId: String,
        recipientDeviceId: String,
        local: E2EEDevicePrivateState,
        peer: E2EEDeviceRegistration,
        peerOneTimePreKey: E2EEPublicPreKey?,
        messageId: String,
        plaintext: Data
    ) throws -> (session: E2EESessionState, envelope: E2EEMessageEnvelope) {
        try verifySignedPreKey(device: peer)
        let identityPrivate = try agreementPrivate(
            local.identityPrivateKey,
            name: "identity"
        )
        let ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
        let peerIdentity = try agreementPublic(peer.identityKey, name: "peer-identity")
        let peerSignedPreKey = try agreementPublic(
            peer.signedPreKey.publicKey,
            name: "peer-signed-prekey"
        )
        var sharedSecrets = [
            try dh(identityPrivate, peerSignedPreKey),
            try dh(ephemeralPrivate, peerIdentity),
            try dh(ephemeralPrivate, peerSignedPreKey)
        ]
        if let oneTime = peerOneTimePreKey {
            sharedSecrets.append(try dh(
                ephemeralPrivate,
                agreementPublic(oneTime.publicKey, name: "peer-one-time-prekey")
            ))
        }
        let material = sharedSecrets.dropFirst().reduce(sharedSecrets[0]) { $0 + $1 }
        let keyMaterial = deriveX3DHKeys(material)
        let sessionId = base64URL(Data(SHA256.hash(data: material)))
        let session = E2EESessionState(
            protocolVersion: E2EEFoundationConfig.protocolVersion,
            sessionId: sessionId,
            rootKey: keyMaterial.root,
            sendChainKey: keyMaterial.initiatorSend,
            receiveChainKey: keyMaterial.initiatorReceive,
            sendCounter: 0,
            receiveCounter: 0
        )
        let ephemeralText = base64URL(ephemeralPrivate.publicKey.rawRepresentation)
        let oneTimeID = peerOneTimePreKey?.id
        let aad = associatedData(
            sessionId: sessionId,
            senderUserId: initiatorUserId,
            senderDeviceId: initiatorDeviceId,
            recipientUserId: recipientUserId,
            recipientDeviceId: recipientDeviceId,
            ephemeralKey: ephemeralText,
            signedPreKeyId: peer.signedPreKey.id,
            oneTimePreKeyId: oneTimeID
        )
        let nonce = randomNonce()
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: SymmetricKey(data: keyMaterial.initiatorSend),
            nonce: try ChaChaPoly.Nonce(data: nonce),
            authenticating: aad
        )
        return (
            session,
            E2EEMessageEnvelope(
                version: E2EEFoundationConfig.protocolVersion,
                sessionId: sessionId,
                messageId: messageId,
                senderUserId: initiatorUserId,
                senderDeviceId: initiatorDeviceId,
                senderIdentityKey: base64URL(identityPrivate.publicKey.rawRepresentation),
                recipientUserId: recipientUserId,
                recipientDeviceId: recipientDeviceId,
                ephemeralKey: ephemeralText,
                signedPreKeyId: peer.signedPreKey.id,
                oneTimePreKeyId: oneTimeID,
                nonce: base64URL(nonce),
                ciphertext: base64URL(sealed.combined),
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        )
    }

    static func acceptInitialEnvelope(
        _ envelope: E2EEMessageEnvelope,
        local: E2EEDevicePrivateState
    ) throws -> (session: E2EESessionState, plaintext: Data) {
        guard envelope.version == E2EEFoundationConfig.protocolVersion,
              envelope.recipientDeviceId == local.deviceId,
              envelope.signedPreKeyId == local.signedPreKey.id else {
            throw E2EEProtocolError.invalidEnvelope
        }
        guard let oneTimeID = envelope.oneTimePreKeyId else {
            throw E2EEProtocolError.missingOneTimePreKey
        }
        guard let oneTime = local.oneTimePreKeys.first(where: { $0.id == oneTimeID }) else {
            throw E2EEProtocolError.missingOneTimePreKey
        }
        let identityPrivate = try agreementPrivate(
            local.identityPrivateKey,
            name: "identity"
        )
        let signedPreKeyPrivate = try agreementPrivate(
            local.signedPreKey.privateKey,
            name: "signed-prekey"
        )
        let oneTimePrivate = try agreementPrivate(
            oneTime.privateKey,
            name: "one-time-prekey"
        )
        let peerIdentity = try agreementPublic(
            envelope.senderIdentityKey,
            name: "peer-identity"
        )
        let ephemeral = try agreementPublic(
            envelope.ephemeralKey,
            name: "ephemeral"
        )
        let material = [
            try dh(signedPreKeyPrivate, peerIdentity),
            try dh(identityPrivate, ephemeral),
            try dh(signedPreKeyPrivate, ephemeral),
            try dh(oneTimePrivate, ephemeral)
        ].dropFirst().reduce(
            try dh(signedPreKeyPrivate, peerIdentity)
        ) { $0 + $1 }
        let sessionId = base64URL(Data(SHA256.hash(data: material)))
        guard sessionId == envelope.sessionId else {
            throw E2EEProtocolError.invalidEnvelope
        }
        let keyMaterial = deriveX3DHKeys(material)
        let session = E2EESessionState(
            protocolVersion: E2EEFoundationConfig.protocolVersion,
            sessionId: sessionId,
            rootKey: keyMaterial.root,
            sendChainKey: keyMaterial.recipientSend,
            receiveChainKey: keyMaterial.recipientReceive,
            sendCounter: 0,
            receiveCounter: 0
        )
        let aad = associatedData(
            sessionId: sessionId,
            senderUserId: envelope.senderUserId,
            senderDeviceId: envelope.senderDeviceId,
            recipientUserId: envelope.recipientUserId,
            recipientDeviceId: envelope.recipientDeviceId,
            ephemeralKey: envelope.ephemeralKey,
            signedPreKeyId: envelope.signedPreKeyId,
            oneTimePreKeyId: envelope.oneTimePreKeyId
        )
        guard let combined = data(base64URL: envelope.ciphertext) else {
            throw E2EEProtocolError.invalidEnvelope
        }
        do {
            let box = try ChaChaPoly.SealedBox(combined: combined)
            let plaintext = try ChaChaPoly.open(
                box,
                using: SymmetricKey(data: keyMaterial.recipientReceive),
                authenticating: aad
            )
            return (session, plaintext)
        } catch {
            throw E2EEProtocolError.authenticationFailed
        }
    }

    static func runSelfTest() throws {
        let alice = try generateDeviceState(
            deviceId: "alice-device",
            oneTimePreKeyStart: 1,
            oneTimePreKeyCount: 2
        )
        let bob = try generateDeviceState(
            deviceId: "bob-device",
            oneTimePreKeyStart: 101,
            oneTimePreKeyCount: 2
        )
        let alicePublic = try publicRegistration(for: alice)
        let bobPublic = try publicRegistration(for: bob)
        _ = try publicRegistration(for: bob)
        let message = Data("xingyan e2ee foundation".utf8)
        let started = try startInitiatorSession(
            initiatorUserId: "alice",
            initiatorDeviceId: alice.deviceId,
            recipientUserId: "bob",
            recipientDeviceId: bob.deviceId,
            local: alice,
            peer: bobPublic,
            peerOneTimePreKey: bobPublic.oneTimePreKeys.first,
            messageId: "selftest-message",
            plaintext: message
        )
        let accepted = try acceptInitialEnvelope(started.envelope, local: bob)
        guard accepted.plaintext == message,
              accepted.session.sessionId == started.session.sessionId,
              accepted.session.receiveChainKey == started.session.sendChainKey else {
            throw E2EEProtocolError.authenticationFailed
        }
        var tampered = started.envelope
        var bytes = data(base64URL: tampered.ciphertext) ?? Data()
        if !bytes.isEmpty { bytes[bytes.count - 1] ^= 0x01 }
        tampered.ciphertext = base64URL(bytes)
        do {
            _ = try acceptInitialEnvelope(tampered, local: bob)
            throw E2EEProtocolError.authenticationFailed
        } catch E2EEProtocolError.authenticationFailed {
            // Expected.
        }
        _ = alicePublic
    }

    private static func deriveX3DHKeys(_ material: Data) -> (
        root: Data,
        initiatorSend: Data,
        initiatorReceive: Data,
        recipientSend: Data,
        recipientReceive: Data
    ) {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: Data(repeating: 0, count: 32),
            info: Data("xingyan-e2ee-x3dh-v1".utf8),
            outputByteCount: 96
        )
        let bytes = key.withUnsafeBytes { Data($0) }
        let root = Data(bytes.prefix(32))
        let initiatorSend = Data(bytes.dropFirst(32).prefix(32))
        let initiatorReceive = Data(bytes.dropFirst(64).prefix(32))
        return (root, initiatorSend, initiatorReceive, initiatorReceive, initiatorSend)
    }

    private static func associatedData(
        sessionId: String,
        senderUserId: String,
        senderDeviceId: String,
        recipientUserId: String,
        recipientDeviceId: String,
        ephemeralKey: String,
        signedPreKeyId: Int,
        oneTimePreKeyId: Int?
    ) -> Data {
        let value = [
            "xingyan-e2ee-v1",
            sessionId,
            senderUserId,
            senderDeviceId,
            recipientUserId,
            recipientDeviceId,
            ephemeralKey,
            String(signedPreKeyId),
            String(oneTimePreKeyId ?? 0)
        ].joined(separator: "|")
        return Data(value.utf8)
    }

    private static func agreementPrivate(
        _ encoded: String,
        name: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let bytes = data(base64URL: encoded) else {
            throw E2EEProtocolError.invalidKey(name)
        }
        do {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
        } catch {
            throw E2EEProtocolError.invalidKey(name)
        }
    }

    private static func agreementPublic(
        _ encoded: String,
        name: String
    ) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let bytes = data(base64URL: encoded) else {
            throw E2EEProtocolError.invalidKey(name)
        }
        do {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
        } catch {
            throw E2EEProtocolError.invalidKey(name)
        }
    }

    private static func signingPrivate(
        _ encoded: String
    ) throws -> Curve25519.Signing.PrivateKey {
        guard let bytes = data(base64URL: encoded) else {
            throw E2EEProtocolError.invalidKey("signing")
        }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
        } catch {
            throw E2EEProtocolError.invalidKey("signing")
        }
    }

    private static func signingPublic(
        _ encoded: String
    ) throws -> Curve25519.Signing.PublicKey {
        guard let bytes = data(base64URL: encoded) else {
            throw E2EEProtocolError.invalidKey("signing")
        }
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: bytes)
        } catch {
            throw E2EEProtocolError.invalidKey("signing")
        }
    }

    private static func dh(
        _ privateKey: Curve25519.KeyAgreement.PrivateKey,
        _ publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> Data {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return secret.withUnsafeBytes { Data($0) }
    }

    private static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<12).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(base64URL value: String) -> Data? {
        var text = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        return Data(base64Encoded: text)
    }
}
