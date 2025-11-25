
import Foundation

extension UserDefaults {
    static let shared = UserDefaults(suiteName: "group.dev.idog.simplelivetvos")!
    private static let queue = DispatchQueue(label: "com.lision.simplelivetvos.userdefaults.queue")

    func synchronized() -> UserDefaults {
        return UserDefaults(suiteName: "group.dev.idog.simplelivetvos")!
    }

    func set(_ value: Any?, forKey key: String, synchronize: Bool) {
        UserDefaults.queue.async {
            self.set(value, forKey: key)
            if synchronize {
                self.synchronize()
            }
        }
    }

    func value(forKey key: String, synchronize: Bool) -> Any? {
        var result: Any?
        UserDefaults.queue.sync {
            result = self.value(forKey: key)
        }
        return result
    }
}
