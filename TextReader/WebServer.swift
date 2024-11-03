import Network

class WebServer: NSObject {
    private var listener: NWListener?
    private var isRunning = false
    var onFileReceived: ((String, String) -> Void)?
    
    func start() -> String? {
        let parameters = NWParameters.tcp
        listener = try? NWListener(using: parameters, on: 8080)
        
        listener?.newConnectionHandler = { [weak self] connection in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("客户端已连接")
                case .failed(let error):
                    print("连接失败: \(error)")
                case .cancelled:
                    print("连接已取消")
                default:
                    break
                }
            }
            
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
                if let data = data, let request = String(data: data, encoding: .utf8) {
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html\r
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
                    
                    if request.contains("Content-Type: multipart/form-data") {
                        if let boundaryStart = request.range(of: "boundary="),
                           let headerEnd = request.range(of: "\r\n\r\n") {
                            let boundary = String(request[boundaryStart.upperBound...]).components(separatedBy: "\r\n").first!
                            let body = String(request[headerEnd.upperBound...])
                            
                            print("收到文件上传请求")
                            print("boundary: \(boundary)")
                            
                            if let filenameRange = request.range(of: "filename=\""),
                               let filenameEnd = request[filenameRange.upperBound...].range(of: "\"") {
                                let filename = String(request[filenameRange.upperBound..<filenameEnd.lowerBound])
                                print("文件名: \(filename)")
                                
                                if let fileStart = body.range(of: "\r\n\r\n"),
                                   let fileEnd = body.range(of: "--\(boundary)--") {
                                    let fileContent = String(body[fileStart.upperBound..<fileEnd.lowerBound])
                                    print("文件内容长度: \(fileContent.count)")
                                    
                                    DispatchQueue.main.async {
                                        self?.onFileReceived?(filename, fileContent)
                                    }
                                    
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
                                    connection.send(content: successResponse.data(using: .utf8), completion: .idempotent)
                                } else {
                                    let errorResponse = """
                                    HTTP/1.1 400 Bad Request\r
                                    Content-Type: text/html; charset=utf-8\r
                                    Connection: close\r
                                    \r
                                    <html><body><h1>文件上传失败：无法解析文件内容</h1></body></html>
                                    """
                                    connection.send(content: errorResponse.data(using: .utf8), completion: .idempotent)
                                }
                            }
                        }
                    } else {
                        connection.send(content: response.data(using: .utf8), completion: .idempotent)
                    }
                }
                
                if error != nil || isComplete {
                    connection.cancel()
                }
            }
            
            connection.start(queue: .main)
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed(let error):
                print("启动服务器失败: \(error)")
                self?.isRunning = false
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
        return getLocalIPAddress()
    }
    
    func stop() {
        listener?.cancel()
        isRunning = false
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
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface?.ifa_addr,
                              socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                              &hostname,
                              socklen_t(hostname.count),
                              nil,
                              0,
                              NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
} 