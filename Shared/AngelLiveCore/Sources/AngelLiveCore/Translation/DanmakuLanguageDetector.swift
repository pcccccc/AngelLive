import Foundation

/// Short chat replies still carry a reliable language signal when their letters
/// use Hangul. Keep the conservative title detector for other scripts and for
/// mixed-language messages.
struct NaturalDanmakuLanguageDetector: RoomTitleLanguageDetecting {
    func sourceLanguage(for text: String) -> String? {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        if !letters.isEmpty, letters.allSatisfy(Self.isHangul) {
            return "ko"
        }
        return NaturalRoomTitleLanguageDetector().sourceLanguage(for: text)
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F,
             0xAC00...0xD7A3, 0xD7B0...0xD7FF:
            true
        default:
            false
        }
    }
}
