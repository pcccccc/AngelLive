import Foundation

/// Decryption methods supported by the native playback adapter.
public enum LivePlaybackDecryptionMethod: String, Codable, Sendable {
    case cenc

    public init(from decoder: Decoder) throws {
        do {
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let method = Self(rawValue: value) else { throw ValidationError.unsupportedMethod }
            self = method
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported playback decryption method."
            ))
        }
    }

    private enum ValidationError: Error { case unsupportedMethod }
}

/// A validated key supplied by a playback plugin, scoped to one quality/session.
/// CENC keys must contain exactly 32 ASCII hexadecimal characters (16 bytes).
/// Whitespace, prefixes and other encodings are rejected.
public struct LivePlaybackDecryption: Codable, Sendable, Equatable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let method: LivePlaybackDecryptionMethod
    public let key: String

    public enum ValidationError: Error, Sendable, LocalizedError {
        case invalidKey

        public var errorDescription: String? {
            "Playback decryption key must contain exactly 32 ASCII hexadecimal characters."
        }
    }

    public init(method: LivePlaybackDecryptionMethod, key: String) throws {
        guard key.utf8.count == 32,
              key.utf8.allSatisfy({
                  (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
              }) else {
            throw ValidationError.invalidKey
        }
        self.method = method
        self.key = key.lowercased()
    }

    private enum CodingKeys: String, CodingKey { case method, key }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                method: container.decode(LivePlaybackDecryptionMethod.self, forKey: .method),
                key: container.decode(String.self, forKey: .key)
            )
        } catch {
            // Do not retain underlying decoder errors: they may contain supplied values.
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid playback decryption declaration."
            ))
        }
    }

    public var description: String { "LivePlaybackDecryption(method: \(method.rawValue), key: <redacted>)" }
    public var debugDescription: String { description }
}
