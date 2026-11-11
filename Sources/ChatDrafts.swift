import Combine
import Foundation

final class ChatDraftStore: ObservableObject {
    static let shared = ChatDraftStore()

    private let storageKey = "chris.chatDrafts.v1"
    private var entries: [String: String]

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) {
            entries = saved.compactMapValues { $0 as? String }
        } else {
            entries = [:]
        }
    }

    func text(for chatId: String) -> String {
        guard !chatId.isEmpty else { return "" }
        return entries[chatId] ?? ""
    }

    func set(_ text: String, for chatId: String) {
        guard !chatId.isEmpty else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clear(chatId)
            return
        }
        guard entries[chatId] != text else { return }
        entries[chatId] = text
        persist(notify: true)
    }

    func clear(_ chatId: String) {
        guard !chatId.isEmpty, entries.removeValue(forKey: chatId) != nil else { return }
        persist(notify: true)
    }

    private func persist(notify: Bool) {
        if notify {
            objectWillChange.send()
        }
        UserDefaults.standard.set(entries, forKey: storageKey)
    }
}
