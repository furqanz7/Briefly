import Foundation

struct AppCachedValue<Value: Codable>: Codable {
    let storedAt: Date
    let value: Value
}

enum AppFeedCache {
    private static let directoryName = "BrieflyFeedCache"

    static func save<Value: Codable>(_ value: Value, key: String) {
        guard let fileURL = fileURL(for: key) else { return }

        do {
            let envelope = AppCachedValue(storedAt: .now, value: value)
            let data = try JSONEncoder.supabase.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("[AppFeedCache] Failed saving \(key): \(error)")
            #endif
        }
    }

    static func load<Value: Codable>(_ type: Value.Type, key: String, maxAge: TimeInterval) -> AppCachedValue<Value>? {
        guard let fileURL = fileURL(for: key) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder.supabase.decode(AppCachedValue<Value>.self, from: data)
            guard Date().timeIntervalSince(envelope.storedAt) <= maxAge else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return envelope
        } catch {
            return nil
        }
    }

    private static func fileURL(for key: String) -> URL? {
        guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directoryURL = cacheURL.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        return directoryURL.appendingPathComponent(fileName(for: key))
    }

    private static func fileName(for key: String) -> String {
        let safe = key.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }
        .joined()
        return "\(safe).json"
    }
}
