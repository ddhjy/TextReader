import Network
import Foundation

class WebServer: NSObject {
    private var listener: NWListener?
    private var isRunning = false
    var onFileReceived: ((String, String) -> Void)?
    
    func start() -> String? {
        let parameters = NWParameters.tcp
        listener = try? NWListener(using: parameters, on: 8080)
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                print("服务器已启动")
            case .failed(let error):
                print("启动服务器失败: \(error)")
                self?.isRunning = false
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener?.start(queue: .main)
        return getLocalIPAddress()
    }
    
    func stop() {
        listener?.cancel()
        isRunning = false
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("客户端已连接")
                self.receiveData(on: connection)
            case .failed(let error):
                print("连接失败: \(error)")
            case .cancelled:
                print("连接已取消")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func receiveData(on connection: NWConnection) {
        // 第一次接收数据，判断请求类型
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            if let error = error {
                print("接收数据错误: \(error)")
                return
            }
            
            if let data = data, let request = String(data: data, encoding: .utf8) {
                print("接收到数据大小: \(data.count) 字节")
                
                // 如果是文件上传请求，使用缓冲区模式接收
                if request.contains("Content-Type: multipart/form-data") {
                    print("检测到文件上传请求，切换到缓冲区模式")
                    self?.receiveFileUpload(connection: connection, initialData: data)
                } else {
                    // 普通请求直接处理
                    print("普通请求，直接处理")
                    self?.processRequest(request, on: connection)
                }
            } else {
                print("初始数据转换失败")
                connection.cancel()
            }
        }
    }
    
    // 新增方法处理文件上传
    private func receiveFileUpload(connection: NWConnection, initialData: Data) {
        var buffer = initialData
        
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
                if let error = error {
                    print("接收文件数据错误: \(error)")
                    return
                }
                
                if let data = data {
                    print("接收到文件数据片段大小: \(data.count) 字节")
                    buffer.append(data)
                    print("当前文件总数据大小: \(buffer.count) 字节")
                }
                
                if isComplete {
                    print("文件数据接收完成，开始处理")
                    // 尝试将整个数据转换为字符串
                    if let requestString = String(data: buffer, encoding: .utf8) {
                        print("数据成功转换为字符串，长度: \(requestString.count)")
                        print("请求头部分:\n\(requestString.prefix(500))")
                        
                        // 解析boundary
                        guard let boundaryStart = requestString.range(of: "boundary="),
                              let headerEnd = requestString.range(of: "\r\n\r\n") else {
                            print("无法找到boundary或请求头结束标记")
                            self?.sendErrorResponse(on: connection, message: "请求格式错误")
                            return
                        }
                        
                        let boundary = "--" + requestString[boundaryStart.upperBound...].components(separatedBy: "\r\n").first!
                        print("解析到boundary: \(boundary)")
                        
                        // 解析文件名
                        guard let filenameRange = requestString.range(of: "filename=\""),
                              let filenameEnd = requestString[filenameRange.upperBound...].range(of: "\"") else {
                            print("无法找到文件名")
                            self?.sendErrorResponse(on: connection, message: "无法获取文件名")
                            return
                        }
                        
                        let filename = String(requestString[filenameRange.upperBound..<filenameEnd.lowerBound])
                        print("解析到文件名: \(filename)")
                        
                        // 解析文件内容
                        let boundaryEnd = "\(boundary)--"
                        guard let contentStart = requestString.range(of: "\r\n\r\n", range: headerEnd.upperBound..<requestString.endIndex),
                              let contentEnd = requestString.range(of: boundaryEnd) else {
                            print("无法找到文件内容边界")
                            self?.sendErrorResponse(on: connection, message: "无法解析文件内容")
                            return
                        }
                        
                        let fileContent = String(requestString[contentStart.upperBound..<contentEnd.lowerBound])
                        print("成功提取文件内容，长度: \(fileContent.count)")
                        print("文件内容前100个字符: \(fileContent.prefix(100))")
                        
                        DispatchQueue.main.async {
                            self?.onFileReceived?(filename, fileContent)
                        }
                        
                        self?.sendSuccessResponse(on: connection, filename: filename)
                    } else {
                        print("数据转换为字符串失败")
                        print("数据前100字节: \(buffer.prefix(100).map { String(format: "%02x", $0) }.joined())")
                        self?.sendErrorResponse(on: connection, message: "数据编码错误")
                    }
                } else if error == nil {
                    receive()
                }
            }
        }
        
        receive()
    }
    
    private func processRequest(_ request: String, on connection: NWConnection) {
        print("收到请求:\n\(request.prefix(200))...")
        
        if request.contains("Content-Type: multipart/form-data") {
            print("检测到文件上传请求")
            guard let boundaryStart = request.range(of: "boundary="),
                  let headerEnd = request.range(of: "\r\n\r\n") else {
                print("解析失败: 未找到boundary或请求头结束标记")
                sendErrorResponse(on: connection, message: "无法找到boundary")
                return
            }
            
            let boundary = "--" + request[boundaryStart.upperBound...].components(separatedBy: "\r\n").first!
            print("解析到boundary: \(boundary)")
            let body = String(request[headerEnd.upperBound...])
            
            if let filenameRange = request.range(of: "filename=\""),
               let filenameEnd = request[filenameRange.upperBound...].range(of: "\"") {
                let filename = String(request[filenameRange.upperBound..<filenameEnd.lowerBound])
                print("解析到文件名: \(filename)")
                
                let boundaryEnd = "\(boundary)--"
                if let fileContentStart = body.range(of: "\r\n\r\n"),
                   let fileContentEnd = body.range(of: boundaryEnd) {
                    let fileContent = String(body[fileContentStart.upperBound..<fileContentEnd.lowerBound])
                    print("成功提取文件内容，长度: \(fileContent.count) 字符")
                    
                    DispatchQueue.main.async {
                        self.onFileReceived?(filename, fileContent)
                    }
                    
                    sendSuccessResponse(on: connection, filename: filename)
                } else {
                    print("解析失败: 无法在请求体中找到文件内容的起始或结束位置")
                    print("请求体片段:\n\(body.prefix(200))...")
                    sendErrorResponse(on: connection, message: "文件内容解析失败")
                }
            } else {
                print("解析失败: 未找到filename字段")
                sendErrorResponse(on: connection, message: "文件名解析失败")
            }
        } else {
            print("普通请求，发送上传表单")
            sendUploadForm(on: connection)
        }
    }
    
    private func sendUploadForm(on connection: NWConnection) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html>
            <head>
                <meta charset="utf-8">
                <title>文件上传</title>
            </head>
            <body>
                <h1>选择要上传的电子书</h1>
                <form action="/upload" method="post" enctype="multipart/form-data">
                    <input type="file" name="book" accept=".epub,.pdf,.txt">
                    <input type="submit" value="上传">
                </form>
            </body>
        </html>
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func sendSuccessResponse(on connection: NWConnection, filename: String) {
        let successResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html>
            <head><meta charset="utf-8"></head>
            <body>
                <h1>文件上传成功！</h1>
                <p>文件名: \(filename)</p>
                <script>setTimeout(function() { window.location.href = '/'; }, 2000);</script>
            </body>
        </html>
        """
        connection.send(content: successResponse.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func sendErrorResponse(on connection: NWConnection, message: String) {
        let errorResponse = """
        HTTP/1.1 400 Bad Request\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html><body><h1>\(message)</h1></body></html>
        """
        connection.send(content: errorResponse.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                0,
                                NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
            ptr = interface.ifa_next
        }
        return address
    }
}
