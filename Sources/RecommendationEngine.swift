import Foundation

enum RecommendationAction: String, Codable, CaseIterable {
    case exposure
    case click
    case play
    case complete
    case skip
    case like
    case unlike
    case share
    case search
}

final class RecommendationEventStore {
    static let shared = RecommendationEventStore()

    private struct Stat: Codable {
        var counts: [String: Int] = [:]
        var lastAt: Double = 0
    }

    private let lock = NSLock()
    private let key: String
    private var stats: [String: Stat]

    private init() {
        key = "chris.recommendation.v1." + API.shared.cacheNamespace
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Stat].self, from: data) {
            stats = saved
        } else {
            stats = [:]
        }
    }

    func record(_ itemId: String, _ action: RecommendationAction, weight: Int = 1) {
        guard !itemId.isEmpty, weight > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        var stat = stats[itemId] ?? Stat()
        stat.counts[action.rawValue, default: 0] += weight
        stat.lastAt = Date().timeIntervalSince1970
        stats[itemId] = stat

        if stats.count > 4_000 {
            stats = Dictionary(uniqueKeysWithValues:
                stats.sorted { $0.value.lastAt > $1.value.lastAt }
                    .prefix(3_000)
                    .map { ($0.key, $0.value) })
        }
        persist()
    }

    func score(_ itemId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let stat = stats[itemId] else { return 0 }

        func count(_ action: RecommendationAction) -> Double {
            Double(stat.counts[action.rawValue] ?? 0)
        }

        let ageDays = max(0, Date().timeIntervalSince1970 - stat.lastAt) / 86_400
        let decay = exp(-ageDays / 28)
        let raw = count(.click) * 1.8
            + count(.play) * 2.4
            + count(.complete) * 5.5
            + count(.like) * 9
            + count(.share) * 7.5
            + count(.search) * 1.2
            - count(.skip) * 5.2
            - count(.unlike) * 8
            - count(.exposure) * 0.05
        return max(-24, min(80, raw)) * decay
    }

    func quality(_ itemId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let stat = stats[itemId] else { return 0.5 }

        func count(_ action: RecommendationAction) -> Double {
            Double(stat.counts[action.rawValue] ?? 0)
        }

        let exposure = count(.exposure)
        let clicks = count(.click)
        let plays = count(.play)
        let completes = count(.complete)
        let skips = count(.skip)
        let likes = count(.like)
        let shares = count(.share)

        // Bayesian smoothing: sparse items stay near neutral instead of being
        // promoted or buried by one accidental tap.
        let clickRate = (clicks + 2.0) / (exposure + 20.0)
        let playRate = (plays + 2.8) / (clicks + 20.0)
        let finishRate = (completes + 9.0) / (plays + 20.0)
        let likeRate = (likes + 0.9) / (plays + 25.0)
        let shareRate = (shares + 0.2) / (plays + 30.0)
        let skipRate = (skips + 3.0) / (plays + 20.0)

        let value = clickRate * 0.17
            + playRate * 0.21
            + finishRate * 0.25
            + likeRate * 1.8
            + shareRate * 2.6
            + max(0, 1 - skipRate) * 0.08
        return max(0, min(1, value))
    }

    func exposureCount(_ itemId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stats[itemId]?.counts[RecommendationAction.exposure.rawValue] ?? 0
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        stats = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
