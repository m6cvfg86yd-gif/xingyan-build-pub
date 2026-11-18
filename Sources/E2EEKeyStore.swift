import Foundation

enum E2EEKeyStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func storageKey(userId: String, deviceId: String) -> String {
        "device.v1.\(userId).\(deviceId)"
    }

    static func load(userId: String, deviceId: String) -> E2EEDevicePrivateState? {
        guard !userId.isEmpty, !deviceId.isEmpty,
              let data = Keychain.getDeviceOnlyData(
                storageKey(userId: userId, deviceId: deviceId)
              ) else { return nil }
        return try? decoder.decode(E2EEDevicePrivateState.self, from: data)
    }

    @discardableResult
    static func generateIfNeeded(
        userId: String,
        deviceId: String,
        oneTimePreKeyCount: Int = 50
    ) throws -> E2EEDevicePrivateState {
        if let existing = load(userId: userId, deviceId: deviceId),
           existing.deviceId == deviceId {
            return existing
        }
        let state = try E2EEProtocol.generateDeviceState(
            deviceId: deviceId,
            oneTimePreKeyCount: oneTimePreKeyCount
        )
        try save(state, userId: userId)
        return state
    }

    static func save(_ state: E2EEDevicePrivateState, userId: String) throws {
        let key = storageKey(userId: userId, deviceId: state.deviceId)
        let data = try encoder.encode(state)
        Keychain.setDeviceOnly(data, for: key)
        guard Keychain.getDeviceOnlyData(key) == data else {
            throw E2EEProtocolError.invalidKey("keychain-store")
        }
    }

    static func registration(
        userId: String,
        deviceId: String
    ) throws -> E2EEDeviceRegistration? {
        guard E2EEFoundationConfig.enabled,
              let state = load(userId: userId, deviceId: deviceId) else {
            return nil
        }
        return try E2EEProtocol.publicRegistration(for: state)
    }

    static func clear(userId: String, deviceId: String) {
        guard !userId.isEmpty, !deviceId.isEmpty else { return }
        Keychain.removeDeviceOnly(storageKey(userId: userId, deviceId: deviceId))
    }
}
