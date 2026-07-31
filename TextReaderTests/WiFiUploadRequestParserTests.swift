import Foundation
import Testing
@testable import TextReader

struct WiFiUploadRequestParserTests {
    @Test
    func parsesHeadersWithoutDecodingPartialUTF8Body() throws {
        let header = """
        POST /upload HTTP/1.1\r
        Host: 127.0.0.1:8080\r
        Content-Type: multipart/form-data; boundary=test-boundary\r
        Content-Length: 3\r
        \r
        """
        var request = Data(header.utf8)
        request.append(contentsOf: [0xE8, 0xA2])

        #expect(String(data: request, encoding: .utf8) == nil)

        let head = try #require(WiFiUploadRequestParser.parseHead(from: request))
        #expect(head.method == "POST")
        #expect(head.path == "/upload")
        #expect(head.contentLength == 3)
        #expect(head.multipartBoundary == "test-boundary")
        #expect(!WiFiUploadRequestParser.isBodyComplete(in: request, head: head))
    }

    @Test
    func parsesCompleteMultipartUploadAlreadyPresentInFirstRead() throws {
        let content = "真正的勇气，是敢于接受现在的自己。"
        let request = makeMultipartRequest(
            boundary: "first-read-boundary",
            fileName: "被讨厌的勇气.txt",
            content: Data(content.utf8)
        )

        let head = try #require(WiFiUploadRequestParser.parseHead(from: request))
        #expect(WiFiUploadRequestParser.isBodyComplete(in: request, head: head))
        #expect(WiFiUploadRequestParser.completeRequestData(from: request, head: head) == request)
        #expect(WiFiUploadRequestParser.fileNameIfAvailable(in: request, head: head) == "被讨厌的勇气.txt")

        let upload = try WiFiUploadRequestParser.parseUpload(from: request, head: head)
        #expect(upload.fileName == "被讨厌的勇气.txt")
        #expect(upload.content == content)
    }

    @Test
    func waitsForAllDeclaredBodyBytesBeforeParsing() throws {
        let request = makeMultipartRequest(
            boundary: "split-boundary",
            fileName: "分段.txt",
            content: Data(String(repeating: "中文内容", count: 30_000).utf8)
        )
        let head = try #require(WiFiUploadRequestParser.parseHead(from: request))
        let splitOffset = head.headerLength + (try #require(head.contentLength)) / 2
        let firstChunk = Data(request.prefix(splitOffset))

        #expect(!WiFiUploadRequestParser.isBodyComplete(in: firstChunk, head: head))
        #expect(WiFiUploadRequestParser.completeRequestData(from: firstChunk, head: head) == nil)
        #expect(WiFiUploadRequestParser.isBodyComplete(in: request, head: head))
    }

    @Test
    func stripsUTF8ByteOrderMarkFromUploadedText() throws {
        var content = Data([0xEF, 0xBB, 0xBF])
        content.append(Data("带 BOM 的正文".utf8))
        let request = makeMultipartRequest(
            boundary: "quoted-boundary",
            fileName: "bom.txt",
            content: content,
            quoteBoundary: true
        )

        let head = try #require(WiFiUploadRequestParser.parseHead(from: request))
        let upload = try WiFiUploadRequestParser.parseUpload(from: request, head: head)
        #expect(upload.content == "带 BOM 的正文")
    }

    private func makeMultipartRequest(
        boundary: String,
        fileName: String,
        content: Data,
        quoteBoundary: Bool = false
    ) -> Data {
        var body = Data("--\(boundary)\r\n".utf8)
        body.append(Data("Content-Disposition: form-data; name=\"book\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: text/plain\r\n\r\n".utf8))
        body.append(content)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let boundaryValue = quoteBoundary ? "\"\(boundary)\"" : boundary
        let header = """
        POST /upload HTTP/1.1\r
        Host: 127.0.0.1:8080\r
        Content-Type: multipart/form-data; boundary=\(boundaryValue)\r
        Content-Length: \(body.count)\r
        \r
        """
        var request = Data(header.utf8)
        request.append(body)
        return request
    }
}
