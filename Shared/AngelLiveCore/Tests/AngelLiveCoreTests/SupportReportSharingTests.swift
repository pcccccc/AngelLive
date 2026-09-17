import Foundation
import Testing
@testable import AngelLiveCore

struct SupportReportSharingTests {
    @Test func downloadRequiresExactPathAndReadOnlyMethod() {
        let report = Data("诊断报告".utf8)
        for line in ["GET / HTTP/1.1", "GET /report/other.txt HTTP/1.1", "POST /report/fixture.txt HTTP/1.1", "GET /report/fixture.txt?extra=1 HTTP/1.1"] {
            let response = SupportReportHTTPResponse.make(request: Data((line + "\r\n\r\n").utf8), expectedPath: "/report/fixture.txt", report: report)
            let text = String(decoding: response, as: UTF8.self)
            #expect(text.hasPrefix("HTTP/1.1 404"))
            #expect(!text.contains("诊断报告"))
        }
    }

    @Test func downloadContainsExactUTF8BodyAndDisablesCaching() {
        let report = Data("错误详情\nHTTP 状态: 503\n".utf8)
        let response = SupportReportHTTPResponse.make(request: Data("GET /report/fixture.txt HTTP/1.1\r\nHost: local\r\n\r\n".utf8), expectedPath: "/report/fixture.txt", report: report)
        let text = String(decoding: response, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK"))
        #expect(text.contains("Content-Length: \(report.count)\r\n"))
        #expect(text.contains("Cache-Control: no-store"))
        #expect(response.suffix(report.count) == report)
    }
}
