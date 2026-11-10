import Foundation
import Testing
@testable import AngelLiveCore

@Suite("m3u playlist parser")
struct M3UPlaylistParserTests {
    private static let fixture = """
    #EXTM3U x-tvg-url="https://guide.example.invalid/epg.xml"
    #PLAYLIST:Fixture Playlist
    #EXTINF:-1 tvg-id="a" tvg-name="频道 A" tvg-logo="https://logo.example.invalid/a.png" group-title="分组 A",频道 A
    https://stream.example.invalid/a/index.m3u8
    #EXT-X-APTV-LOGO:ignored
    #EXTINF:-1 tvg-logo="https://logo.example.invalid/b.png" group-title="分组 B",频道 B
    #EXTVLCOPT:http-user-agent=fixture-agent/1.0
    #EXTVLCOPT:http-referrer=https://referer.example.invalid/
    https://stream.example.invalid/b
    #EXTINF:-1 group-title="分组 A",频道 A
    https://backup.example.invalid/a.m3u8
    #EXTINF:-1 group-title="分组 A",频道 A
    https://stream.example.invalid/a/index.m3u8
    #EXTINF:-1,无分组频道
    https://stream.example.invalid/c.flv
    #EXTINF:-1 group-title="公告, 说明",维护时间：2026-8-21 #佛系维护, 勿催
    https://stream.example.invalid/notice
    #EXTINF:-1 group-title="分组 B",不可播放协议
    rtmp://stream.example.invalid/live
    https://stream.example.invalid/bare-without-extinf
    """

    @Test("channels, groups, logos and playlist title")
    func parsesChannels() throws {
        let playlist = try M3UPlaylistParser.parse(Data(Self.fixture.utf8))
        #expect(playlist.title == "Fixture Playlist")
        #expect(playlist.channels.map(\.name) == ["频道 A", "频道 B", "无分组频道", "维护时间：2026-8-21 #佛系维护, 勿催"])
        #expect(playlist.groups == ["分组 A", "分组 B", M3UPlaylistParser.defaultGroupName, "公告, 说明"])
        #expect(playlist.channels[0].logo == "https://logo.example.invalid/a.png")
        #expect(playlist.channels[2].logo == nil)
    }

    @Test("same group and name merge into lines without duplicate URLs")
    func mergesLines() throws {
        let playlist = try M3UPlaylistParser.parse(Data(Self.fixture.utf8))
        #expect(playlist.channels[0].lines.map(\.url) == [
            "https://stream.example.invalid/a/index.m3u8",
            "https://backup.example.invalid/a.m3u8"
        ])
    }

    @Test("VLC options bind to the following URL only")
    func bindsRequestOptions() throws {
        let playlist = try M3UPlaylistParser.parse(Data(Self.fixture.utf8))
        let line = try #require(playlist.channels[1].lines.first)
        #expect(line.userAgent == "fixture-agent/1.0")
        #expect(line.headers["Referer"] == "https://referer.example.invalid/")
        #expect(playlist.channels[2].lines[0].userAgent == nil)
        #expect(playlist.channels[2].lines[0].headers.isEmpty)
    }

    @Test("Kodi stream headers are decoded")
    func kodiHeaders() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="分组 A",频道 K
        #KODIPROP:inputstream.adaptive.stream_headers=User-Agent=fixture%20agent&Referer=https%3A%2F%2Fr.example.invalid%2F
        https://stream.example.invalid/k.m3u8
        """
        let line = try #require(try M3UPlaylistParser.parse(text: text).channels.first?.lines.first)
        #expect(line.userAgent == "fixture agent")
        #expect(line.headers == ["Referer": "https://r.example.invalid/"])
    }

    @Test("EXTGRP is used when group-title is missing")
    func extGroup() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1,频道 G
        #EXTGRP:分组 G
        https://stream.example.invalid/g.m3u8
        """
        #expect(try M3UPlaylistParser.parse(text: text).channels.first?.group == "分组 G")
    }

    @Test("tvg-name is used when the title after the comma is empty")
    func tvgNameFallback() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-name="频道 N" group-title="分组 A",
        https://stream.example.invalid/n.m3u8
        """
        #expect(try M3UPlaylistParser.parse(text: text).channels.first?.name == "频道 N")
    }

    @Test("content sniffing ignores BOM and leading whitespace")
    func sniffing() {
        #expect(M3UPlaylistParser.looksLikePlaylist(Data([0xEF, 0xBB, 0xBF] + Array("\n  #EXTM3U\n".utf8))))
        #expect(!M3UPlaylistParser.looksLikePlaylist(Data("{\"plugins\":[]}".utf8)))
        #expect(!M3UPlaylistParser.looksLikePlaylist(Data("<html>".utf8)))
    }

    @Test("non playlists and empty playlists are rejected")
    func rejections() {
        #expect(throws: M3UPlaylistError.notPlaylist) { try M3UPlaylistParser.parse(Data("{}".utf8)) }
        #expect(throws: M3UPlaylistError.noChannels) { try M3UPlaylistParser.parse(Data("#EXTM3U\n#EXTINF:-1,A\n".utf8)) }
        let oversized = Data("#EXTM3U\n".utf8) + Data(count: M3UPlaylistParser.maxByteCount)
        #expect(throws: M3UPlaylistError.tooLarge) { try M3UPlaylistParser.parse(oversized) }
    }

    @Test("GB18030 text is decoded when UTF-8 fails")
    func gb18030() throws {
        let text = "#EXTM3U\n#EXTINF:-1 group-title=\"分组\",频道\nhttps://stream.example.invalid/x.m3u8\n"
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let data = try #require(text.data(using: encoding))
        #expect(String(data: data, encoding: .utf8) == nil)
        let playlist = try M3UPlaylistParser.parse(data)
        #expect(playlist.channels.first?.name == "频道")
        #expect(playlist.channels.first?.group == "分组")
    }
}

@Suite("HLS master playlist expansion")
struct HLSMasterPlaylistParserTests {
    private let base = URL(string: "https://stream.example.invalid/live/master")!

    @Test("variants are named, resolved and ordered by bandwidth")
    func variants() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        mid/index
        #EXT-X-STREAM-INF:BANDWIDTH=5000000
        https://cdn.example.invalid/high
        #EXT-X-STREAM-INF:BANDWIDTH=800000,NAME="低清"
        /low/index.m3u8
        """
        let variants = try #require(HLSMasterPlaylistParser.variants(in: text, baseURL: base))
        #expect(variants.map(\.title) == ["5000kbps", "720p", "低清"])
        #expect(variants.map(\.url) == [
            "https://cdn.example.invalid/high",
            "https://stream.example.invalid/live/mid/index",
            "https://stream.example.invalid/low/index.m3u8"
        ])
    }

    @Test("masters with separate audio renditions are not expanded")
    func separateAudio() {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="main",DEFAULT=YES,URI="audio/index.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,AUDIO="aud"
        high
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="aud"
        low
        """
        #expect(HLSMasterPlaylistParser.variants(in: text, baseURL: base) == nil)
    }

    @Test("duplicate titles get a bitrate suffix")
    func duplicateTitles() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=7800000,RESOLUTION=1920x1080
        a
        #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
        b
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
        c
        """
        let titles = try #require(HLSMasterPlaylistParser.variants(in: text, baseURL: base)).map(\.title)
        #expect(titles == ["1080p · 7800kbps", "1080p · 6000kbps", "720p"])
    }

    @Test("media playlists are not treated as master")
    func mediaPlaylist() {
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg1.ts\n"
        #expect(HLSMasterPlaylistParser.variants(in: text, baseURL: base) == nil)
    }
}
