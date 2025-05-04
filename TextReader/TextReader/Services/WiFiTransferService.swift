import Network
import Foundation

class WiFiTransferService: ObservableObject {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var serverAddress: String?
    var onFileReceived: ((String, String) -> Void)?
    
    func startServer() -> Bool {
        let parameters = NWParameters.tcp
        guard listener == nil else {
            print("服务器已经运行中")
            return isRunning
        }
        
        listener = try? NWListener(using: parameters, on: 8080)
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self?.isRunning = true
                    if let ipAddress = self?.getLocalIPAddress() {
                        self?.serverAddress = "http://\(ipAddress):8080"
                    }
                }
                print("服务器已启动")
            case .failed(let error):
                print("启动服务器失败: \(error)")
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.serverAddress = nil
                }
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener?.start(queue: .main)
        
        if let ipAddress = getLocalIPAddress() {
            serverAddress = "http://\(ipAddress):8080"
            return true
        } else {
            return false
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverAddress = nil
        }
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
    
    // 处理文件上传
    private func receiveFileUpload(connection: NWConnection, initialData: Data) {
        var buffer = initialData
        print("开始接收文件上传，初始数据大小: \(initialData.count)")
        
        // 添加一个计时器来检测传输是否结束
        var lastReceiveTime = Date()
        var noDataTimer: Timer?
        
        func checkDataComplete() {
            // 如果3秒内没有新数据，认为传输结束
            if Date().timeIntervalSince(lastReceiveTime) >= 3.0 {
                print("检测到传输可能已结束，开始处理数据")
                processReceivedData()
                noDataTimer?.invalidate()
                noDataTimer = nil
            }
        }
        
        func processReceivedData() {
            print("数据接收完成，开始处理文件内容，总大小: \(buffer.count)字节")
            // 尝试检测文件编码
            let encodings: [String.Encoding] = [.utf8]
            var fileContent: String?
            
            for encoding in encodings {
                if let content = String(data: buffer, encoding: encoding) {
                    fileContent = content
                    print("成功使用编码 \(encoding) 转换文件内容")
                    break
                }
            }
            
            if let content = fileContent {
                if let boundaryStart = content.range(of: "boundary="),
                   let headerEnd = content.range(of: "\r\n\r\n") {
                    let boundary = "--" + content[boundaryStart.upperBound...].components(separatedBy: "\r\n").first!
                    print("解析到boundary: \(boundary)")
                    
                    if let filenameRange = content.range(of: "filename=\""),
                       let filenameEnd = content[filenameRange.upperBound...].range(of: "\"") {
                        let filename = String(content[filenameRange.upperBound..<filenameEnd.lowerBound])
                        print("解析到文件名: \(filename)")
                        
                        let boundaryEnd = "\(boundary)--"
                        if let contentStart = content.range(of: "\r\n\r\n", range: headerEnd.upperBound..<content.endIndex),
                           let contentEnd = content.range(of: boundaryEnd) {
                            let fileContent = String(content[contentStart.upperBound..<contentEnd.lowerBound])
                            print("成功提取文件内容，长度: \(fileContent.count)")
                            
                            DispatchQueue.main.async { [weak self] in
                                self?.onFileReceived?(filename, fileContent)
                            }
                            
                            sendSuccessResponse(on: connection, filename: filename)
                            return
                        }
                    }
                }
                sendErrorResponse(on: connection, message: "文件格式解析失败")
            } else {
                print("尝试过的编码都无法解析文件内容")
                sendErrorResponse(on: connection, message: "不支持的文件编码格式")
            }
        }
        
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
                if let error = error {
                    print("接收文件数据错误: \(error)")
                    self?.sendErrorResponse(on: connection, message: "接收数据时发生错误")
                    return
                }
                
                if let data = data {
                    buffer.append(data)
                    lastReceiveTime = Date()
                    print("接收到新数据片段: \(data.count)字节，当前总大小: \(buffer.count)字节")
                    
                    // 重置计时器
                    noDataTimer?.invalidate()
                    noDataTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        checkDataComplete()
                    }
                }
                
                if isComplete {
                    print("收到完成标志，开始处理数据")
                    noDataTimer?.invalidate()
                    processReceivedData()
                } else if error == nil {
                    receive()
                }
            }
        }
        
        // 启动初始计时器
        noDataTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            checkDataComplete()
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
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>文件上传</title>
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                        max-width: 600px;
                        margin: 0 auto;
                        padding: 20px;
                        text-align: center;
                    }
                    .upload-form {
                        border: 2px dashed #ccc;
                        border-radius: 10px;
                        padding: 20px;
                        margin: 20px 0;
                    }
                    .file-input {
                        display: none;
                    }
                    .upload-button {
                        background: #007AFF;
                        color: white;
                        padding: 10px 20px;
                        border: none;
                        border-radius: 5px;
                        font-size: 16px;
                        cursor: pointer;
                    }
                    .file-label {
                        display: block;
                        margin: 10px 0;
                        color: #666;
                    }
                    #selected-file {
                        margin: 10px 0;
                        color: #333;
                    }
                    .error {
                        color: #FF3B30;
                        margin: 10px 0;
                        display: none;
                    }
                </style>
            </head>
            <body>
                <h1>WiFi 传书</h1>
                <div class="upload-form">
                    <form action="/upload" method="post" enctype="multipart/form-data" onsubmit="return validateForm()">
                        <label class="file-label">支持的格式：TXT</label>
                        <input type="file" name="book" accept=".txt" class="file-input" id="file-input" onchange="updateFileName()">
                        <button type="button" class="upload-button" onclick="document.getElementById('file-input').click()">
                            选择文件
                        </button>
                        <div id="selected-file"></div>
                        <div class="error" id="error-message">请选择有效的文本文件</div>
                        <button type="submit" class="upload-button" style="margin-top: 10px;">上传</button>
                    </form>
                </div>
                <script>
                    function updateFileName() {
                        const input = document.getElementById('file-input');
                        const fileInfo = document.getElementById('selected-file');
                        const errorMsg = document.getElementById('error-message');
                        
                        if (input.files.length > 0) {
                            const file = input.files[0];
                            fileInfo.textContent = file.name;
                            
                            if (!file.name.toLowerCase().endsWith('.txt')) {
                                errorMsg.style.display = 'block';
                                return false;
                            }
                            errorMsg.style.display = 'none';
                        } else {
                            fileInfo.textContent = '';
                            errorMsg.style.display = 'none';
                        }
                    }
                    
                    function validateForm() {
                        const input = document.getElementById('file-input');
                        const errorMsg = document.getElementById('error-message');
                        
                        if (input.files.length === 0) {
                            errorMsg.style.display = 'block';
                            return false;
                        }
                        
                        const file = input.files[0];
                        if (!file.name.toLowerCase().endsWith('.txt')) {
                            errorMsg.style.display = 'block';
                            return false;
                        }
                        
                        return true;
                    }
                </script>
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
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                        max-width: 600px;
                        margin: 0 auto;
                        padding: 20px;
                        text-align: center;
                    }
                    .success-icon {
                        color: #34C759;
                        font-size: 48px;
                        margin: 20px 0;
                    }
                    .file-name {
                        color: #666;
                        margin: 10px 0;
                    }
                    .progress {
                        width: 100%;
                        height: 4px;
                        background: #E5E5EA;
                        border-radius: 2px;
                        overflow: hidden;
                        margin: 20px 0;
                    }
                    .progress-bar {
                        width: 0%;
                        height: 100%;
                        background: #34C759;
                        animation: progress 2s ease-in-out forwards;
                    }
                    @keyframes progress {
                        to { width: 100%; }
                    }
                </style>
            </head>
            <body>
                <div class="success-icon">✓</div>
                <h1>上传成功！</h1>
                <p class="file-name">文件名：\(filename)</p>
                <div class="progress">
                    <div class="progress-bar"></div>
                </div>
                <p>正在返回首页...</p>
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
        <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                        max-width: 600px;
                        margin: 0 auto;
                        padding: 20px;
                        text-align: center;
                    }
                    .error-icon {
                        color: #FF3B30;
                        font-size: 48px;
                        margin: 20px 0;
                    }
                    .error-message {
                        color: #666;
                        margin: 10px 0;
                    }
                    .back-button {
                        display: inline-block;
                        background: #007AFF;
                        color: white;
                        padding: 10px 20px;
                        border-radius: 5px;
                        text-decoration: none;
                        margin-top: 20px;
                    }
                </style>
            </head>
            <body>
                <div class="error-icon">✕</div>
                <h1>上传失败</h1>
                <p class="error-message">\(message)</p>
                <a href="/" class="back-button">返回重试</a>
                <script>setTimeout(function() { window.location.href = '/'; }, 3000);</script>
            </body>
        </html>
        """
        connection.send(content: errorResponse.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    func getLocalIPAddress() -> String? {
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