import Foundation

struct WiFiUploadRequestParser {
    struct RequestHead: Equatable {
        let method: String
        let path: String
        let headerLength: Int
        let contentLength: Int?
        let multipartBoundary: String?
    }

    struct Upload: Equatable {
        let fileName: String
        let content: String
    }

    enum ParserError: LocalizedError, Equatable {
        case missingContentLength
        case incompleteBody
        case missingBoundary
        case invalidMultipartBody
        case missingFileName
        case unsupportedTextEncoding

        var errorDescription: String? {
            switch self {
            case .missingContentLength:
                return "请求缺少 Content-Length"
            case .incompleteBody:
                return "文件数据接收不完整"
            case .missingBoundary:
                return "无法找到 multipart boundary"
            case .invalidMultipartBody:
                return "文件格式解析失败"
            case .missingFileName:
                return "文件名解析失败"
            case .unsupportedTextEncoding:
                return "不支持的文件编码格式"
            }
        }
    }

    private static let headerDelimiter = Data("\r\n\r\n".utf8)

    static func parseHead(from data: Data) -> RequestHead? {
        guard let headerRange = data.range(of: headerDelimiter) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = headers["content-length"].flatMap(Int.init)
        let boundary = headers["content-type"].flatMap(multipartBoundary(from:))

        return RequestHead(
            method: requestParts[0].uppercased(),
            path: requestParts[1],
            headerLength: headerRange.upperBound,
            contentLength: contentLength,
            multipartBoundary: boundary
        )
    }

    static func receivedBodyByteCount(in data: Data, head: RequestHead) -> Int {
        max(0, data.count - head.headerLength)
    }

    static func isBodyComplete(in data: Data, head: RequestHead) -> Bool {
        guard let contentLength = head.contentLength,
              contentLength >= 0,
              contentLength <= Int.max - head.headerLength else {
            return false
        }
        return data.count >= head.headerLength + contentLength
    }

    static func completeRequestData(from data: Data, head: RequestHead) -> Data? {
        guard isBodyComplete(in: data, head: head),
              let contentLength = head.contentLength else {
            return nil
        }
        return Data(data.prefix(head.headerLength + contentLength))
    }

    static func fileNameIfAvailable(in data: Data, head: RequestHead) -> String? {
        guard data.count > head.headerLength else { return nil }
        let availableBody = data.suffix(from: head.headerLength).prefix(16_384)
        guard let partHeaderRange = availableBody.range(of: headerDelimiter) else {
            return nil
        }
        let partHeaderData = Data(availableBody[..<partHeaderRange.lowerBound])
        let partHeaders = String(decoding: partHeaderData, as: UTF8.self)
        return quotedParameter(named: "filename", in: partHeaders)
    }

    static func parseUpload(from requestData: Data, head: RequestHead) throws -> Upload {
        guard let contentLength = head.contentLength else {
            throw ParserError.missingContentLength
        }
        guard isBodyComplete(in: requestData, head: head) else {
            throw ParserError.incompleteBody
        }
        guard let boundary = head.multipartBoundary, !boundary.isEmpty else {
            throw ParserError.missingBoundary
        }

        let bodyEnd = head.headerLength + contentLength
        let body = requestData.subdata(in: head.headerLength..<bodyEnd)
        let openingBoundary = Data("--\(boundary)\r\n".utf8)
        guard body.starts(with: openingBoundary) else {
            throw ParserError.invalidMultipartBody
        }

        let partHeadersStart = openingBoundary.count
        guard let partHeaderRange = body.range(
            of: headerDelimiter,
            in: partHeadersStart..<body.endIndex
        ) else {
            throw ParserError.invalidMultipartBody
        }

        let partHeaderData = body.subdata(in: partHeadersStart..<partHeaderRange.lowerBound)
        let partHeaders = String(decoding: partHeaderData, as: UTF8.self)
        guard let fileName = quotedParameter(named: "filename", in: partHeaders), !fileName.isEmpty else {
            throw ParserError.missingFileName
        }

        let fileContentStart = partHeaderRange.upperBound
        let closingBoundary = Data("\r\n--\(boundary)".utf8)
        guard let closingRange = body.range(
            of: closingBoundary,
            options: .backwards,
            in: fileContentStart..<body.endIndex
        ) else {
            throw ParserError.invalidMultipartBody
        }

        var fileData = body.subdata(in: fileContentStart..<closingRange.lowerBound)
        if fileData.starts(with: [0xEF, 0xBB, 0xBF]) {
            fileData.removeFirst(3)
        }
        guard let content = String(data: fileData, encoding: .utf8) else {
            throw ParserError.unsupportedTextEncoding
        }

        return Upload(fileName: fileName, content: content)
    }

    private static func multipartBoundary(from contentType: String) -> String? {
        let components = contentType.split(separator: ";", omittingEmptySubsequences: true)
        guard components.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "multipart/form-data" else {
            return nil
        }

        for component in components.dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "boundary" else {
                continue
            }
            return pair[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private static func quotedParameter(named name: String, in value: String) -> String? {
        let marker = "\(name)=\""
        guard let start = value.range(of: marker, options: .caseInsensitive),
              let end = value[start.upperBound...].firstIndex(of: "\"") else {
            return nil
        }
        return String(value[start.upperBound..<end])
    }
}
