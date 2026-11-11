import CryptoKit
import Foundation

/// Joins a separate video file and audio file into one static DASH manifest, so a
/// single FFmpeg demuxer opens both inputs and the player keeps one audio clock.
enum SeparateAudioManifest {
    /// FFmpeg's DASH demuxer only accepts file and http(s) children; a manifest opened
    /// from a local file inherits a whitelist without http, so it must be widened.
    static let protocolWhitelist = "file,http,https,tcp,tls,crypto,data"
    /// The DASH demuxer forwards this option (not `decryption_key`) to its CENC children.
    static let decryptionKeyOption = "cenc_decryption_key"

    static func xml(videoURL: URL, audioURL: URL) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:DASH:schema:MPD:2011" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" type="static" minBufferTime="PT1.5S">
          <Period>
            <AdaptationSet mimeType="video/mp4"><Representation id="v1"><BaseURL>\(escape(videoURL.absoluteString))</BaseURL></Representation></AdaptationSet>
            <AdaptationSet mimeType="audio/mp4"><Representation id="a1"><BaseURL>\(escape(audioURL.absoluteString))</BaseURL></Representation></AdaptationSet>
          </Period>
        </MPD>
        """
    }

    /// Writes the manifest to a private temporary file. The name is a digest, so signed
    /// URLs never appear in file names.
    static func write(videoURL: URL, audioURL: URL, directory: URL = defaultDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data((videoURL.absoluteString + "\n" + audioURL.absoluteString).utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let fileURL = directory.appendingPathComponent(name).appendingPathExtension("mpd")
        try Data(xml(videoURL: videoURL, audioURL: audioURL).utf8)
            .write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return fileURL
    }

    static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SeparateAudioManifests", isDirectory: true)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
