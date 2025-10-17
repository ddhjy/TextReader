import Network
import Foundation

/// WiFi传输服务，提供无线文件传输功能
class WiFiTransferService: ObservableObject, @unchecked Sendable {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var serverAddress: String?
    
    /// 上传状态
    struct UploadState {
        var fileName: String?
        var receivedBytes: Int
        var totalBytes: Int?
        var startedAt: Date
        var isCompleted: Bool
        var errorMessage: String?
    }
    
    /// 当前上传状态（用于手机端展示进度与错误）
    @Published var uploadState: UploadState?
    var onFileReceived: ((String, String) -> Void)?
    
    /// Starts the WiFi transfer server on port 8080
    /// - Returns: Whether the server started successfully
    func startServer() -> Bool {
        let parameters = NWParameters.tcp
        guard listener == nil else {
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
            case .failed:
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
    
    /// Stops the WiFi transfer server
    func stopServer() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverAddress = nil
        }
    }
    
    /// Handles a new client connection
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveData(on: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    /// Receives initial data from the connection to determine request type
    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            if error != nil {
                return
            }
            
            if let data = data, let request = String(data: data, encoding: .utf8) {
                // 兜底处理预检请求（极端情况下的OPTIONS）
                if request.hasPrefix("OPTIONS ") {
                    self?.sendOptionsPreflight(on: connection)
                    return
                }
                if request.contains("Content-Type: multipart/form-data") {
                    self?.receiveFileUpload(connection: connection, initialData: data)
                } else {
                    self?.processRequest(request, on: connection)
                }
            } else {
                connection.cancel()
            }
        }
    }
    
    /// Handles file upload requests using a buffer to collect all data
    private func receiveFileUpload(connection: NWConnection, initialData: Data) {
        var buffer = initialData
        let startTime = Date()
        var headerEndOffset: Int? = nil
        var declaredContentLength: Int? = nil
        var detectedFileName: String? = nil
        
        // 解析首包中的Header，提取Content-Length
        if let headerDelimiter = "\r\n\r\n".data(using: .utf8),
           let range = buffer.range(of: headerDelimiter) {
            headerEndOffset = range.upperBound
            let headerData = buffer.subdata(in: 0..<range.upperBound)
            if let headerString = String(data: headerData, encoding: .utf8) {
                if let lenLine = headerString.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }) {
                    let numPart = lenLine.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
                    if let n = numPart, let v = Int(n) {
                        declaredContentLength = v
                    }
                }
            }
        }
        
        // 初始化上传状态（注意：receivedBytes统计主体部分长度，若无header分界则暂置0）
        DispatchQueue.main.async { [weak self] in
            let receivedBody = headerEndOffset.map { max(0, buffer.count - $0) } ?? 0
            self?.uploadState = UploadState(
                fileName: detectedFileName,
                receivedBytes: receivedBody,
                totalBytes: declaredContentLength,
                startedAt: startTime,
                isCompleted: false,
                errorMessage: nil
            )
        }
        
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
                if error != nil {
                    self?.sendErrorResponse(on: connection, message: "接收数据时发生错误")
                    // 发布错误状态
                    DispatchQueue.main.async {
                        if var s = self?.uploadState {
                            s.errorMessage = "接收数据时发生错误"
                            s.isCompleted = false
                            self?.uploadState = s
                        } else {
                            self?.uploadState = UploadState(
                                fileName: detectedFileName,
                                receivedBytes: 0,
                                totalBytes: declaredContentLength,
                                startedAt: startTime,
                                isCompleted: false,
                                errorMessage: "接收数据时发生错误"
                            )
                        }
                        // 2秒后清空状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self?.uploadState = nil
                        }
                    }
                    return
                }
                
                if let data = data {
                    buffer.append(data)
                }
                
                // 如果尚未确定header结束位置，尝试再次定位，便于计算主体部分已收字节
                if headerEndOffset == nil, let headerDelimiter = "\r\n\r\n".data(using: .utf8), let range = buffer.range(of: headerDelimiter) {
                    headerEndOffset = range.upperBound
                }
                
                // 尝试从缓冲中解析文件名（仅解析一次）
                if detectedFileName == nil, let contentStr = String(data: buffer, encoding: .utf8) {
                    if let filenameRange = contentStr.range(of: "filename=\"") {
                        if let filenameEnd = contentStr[filenameRange.upperBound...].range(of: "\"") {
                            detectedFileName = String(contentStr[filenameRange.upperBound..<filenameEnd.lowerBound])
                        }
                    }
                }
                
                // 进度更新（如果有Content-Length且已找到header终点）
                if let total = declaredContentLength, let headerEnd = headerEndOffset {
                    let receivedBody = max(0, buffer.count - headerEnd)
                    DispatchQueue.main.async { [weak self] in
                        if var s = self?.uploadState {
                            s.receivedBytes = receivedBody
                            s.totalBytes = total
                            s.fileName = s.fileName ?? detectedFileName
                            self?.uploadState = s
                        } else {
                            self?.uploadState = UploadState(
                                fileName: detectedFileName,
                                receivedBytes: receivedBody,
                                totalBytes: total,
                                startedAt: startTime,
                                isCompleted: false,
                                errorMessage: nil
                            )
                        }
                    }
                    // 若已收满整个Body（等于或超过Content-Length），立即解析
                    if receivedBody >= total {
                        self?.processReceivedData(buffer: buffer, connection: connection)
                        DispatchQueue.main.async { [weak self] in
                            if var s = self?.uploadState {
                                s.receivedBytes = max(receivedBody, total)
                                s.totalBytes = total
                                s.fileName = s.fileName ?? detectedFileName
                                s.isCompleted = true
                                self?.uploadState = s
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self?.uploadState = nil
                            }
                        }
                        return
                    }
                }
                
                if isComplete {
                    // 无Content-Length的兜底解析
                    self?.processReceivedData(buffer: buffer, connection: connection)
                } else if error == nil {
                    receive()
                }
            }
        }
        
        receive()
    }
    
    /// Process received data to extract file content
    private func processReceivedData(buffer: Data, connection: NWConnection) {
        let encodings: [String.Encoding] = [.utf8]
        var fileContent: String?
        var filenameToPublish: String? = nil
        
        for encoding in encodings {
            if let content = String(data: buffer, encoding: encoding) {
                fileContent = content
                break
            }
        }
        
        if let content = fileContent {
            if let boundaryStart = content.range(of: "boundary="),
               let headerEnd = content.range(of: "\r\n\r\n") {
                let boundary = "--" + content[boundaryStart.upperBound...].components(separatedBy: "\r\n").first!
                
                if let filenameRange = content.range(of: "filename=\""),
                   let filenameEnd = content[filenameRange.upperBound...].range(of: "\"") {
                    let filename = String(content[filenameRange.upperBound..<filenameEnd.lowerBound])
                    filenameToPublish = filename
                    
                    let boundaryEnd = "\(boundary)--"
                    if let contentStart = content.range(of: "\r\n\r\n", range: headerEnd.upperBound..<content.endIndex),
                       let contentEnd = content.range(of: boundaryEnd) {
                        let fileContent = String(content[contentStart.upperBound..<contentEnd.lowerBound])
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.onFileReceived?(filename, fileContent)
                            // 上传完成状态留存2秒
                            if var s = self?.uploadState {
                                s.fileName = s.fileName ?? filename
                                s.isCompleted = true
                                self?.uploadState = s
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    self?.uploadState = nil
                                }
                            }
                        }
                        
                        sendSuccessResponse(on: connection, filename: filename)
                        return
                    }
                }
            }
            sendErrorResponse(on: connection, message: "文件格式解析失败")
            // 发布错误
            DispatchQueue.main.async { [weak self] in
                if var s = self?.uploadState {
                    s.fileName = s.fileName ?? filenameToPublish
                    s.errorMessage = "文件格式解析失败"
                    s.isCompleted = false
                    self?.uploadState = s
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.uploadState = nil
                }
            }
        } else {
            sendErrorResponse(on: connection, message: "不支持的文件编码格式")
            DispatchQueue.main.async { [weak self] in
                if var s = self?.uploadState {
                    s.errorMessage = "不支持的文件编码格式"
                    s.isCompleted = false
                    self?.uploadState = s
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.uploadState = nil
                }
            }
        }
    }
    
    /// Processes HTTP requests and responds appropriately
    private func processRequest(_ request: String, on connection: NWConnection) {
        // 兜底处理预检请求（OPTIONS）
        if request.hasPrefix("OPTIONS ") {
            sendOptionsPreflight(on: connection)
            return
        }
        if request.contains("Content-Type: multipart/form-data") {
            guard let boundaryStart = request.range(of: "boundary="),
                  let headerEnd = request.range(of: "\r\n\r\n") else {
                sendErrorResponse(on: connection, message: "无法找到boundary")
                return
            }
            
            let boundary = "--" + request[boundaryStart.upperBound...].components(separatedBy: "\r\n").first!
            let body = String(request[headerEnd.upperBound...])
            
            if let filenameRange = request.range(of: "filename=\""),
               let filenameEnd = request[filenameRange.upperBound...].range(of: "\"") {
                let filename = String(request[filenameRange.upperBound..<filenameEnd.lowerBound])
                
                let boundaryEnd = "\(boundary)--"
                if let fileContentStart = body.range(of: "\r\n\r\n"),
                   let fileContentEnd = body.range(of: boundaryEnd) {
                    let fileContent = String(body[fileContentStart.upperBound..<fileContentEnd.lowerBound])
                    
                    DispatchQueue.main.async {
                        self.onFileReceived?(filename, fileContent)
                    }
                    
                    sendSuccessResponse(on: connection, filename: filename)
                } else {
                    sendErrorResponse(on: connection, message: "文件内容解析失败")
                }
            } else {
                sendErrorResponse(on: connection, message: "文件名解析失败")
            }
        } else {
            sendUploadForm(on: connection)
        }
    }

    /// Responds to OPTIONS preflight with permissive CORS headers
    private func sendOptionsPreflight(on connection: NWConnection) {
        let resp = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        """
        connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    /// Sends the HTML upload form to the client
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
                    #progress { margin-top: 14px; display: none; }
                    #progress .bar-wrap { width: 100%; height: 4px; background: #E5E5EA; border-radius: 2px; overflow: hidden; }
                    #progress .bar { height: 100%; width: 0%; background: #34C759; }
                    #progress .percent { margin-top: 8px; color: #666; }
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
                        <div id="progress">
                            <div class="bar-wrap"><div id="bar" class="bar"></div></div>
                            <div id="percent" class="percent">0%</div>
                        </div>
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
                    
                    function uploadViaXHR() {
                        const input = document.getElementById('file-input');
                        const errorMsg = document.getElementById('error-message');
                        const progress = document.getElementById('progress');
                        const bar = document.getElementById('bar');
                        const percent = document.getElementById('percent');
                        
                        if (input.files.length === 0) {
                            errorMsg.style.display = 'block';
                            return false;
                        }
                        const file = input.files[0];
                        if (!file.name.toLowerCase().endsWith('.txt')) {
                            errorMsg.style.display = 'block';
                            return false;
                        }
                        errorMsg.style.display = 'none';
                        progress.style.display = 'block';
                        bar.style.width = '0%';
                        percent.textContent = '0%';
                        
                        const fd = new FormData();
                        fd.append('book', file, file.name);
                        const xhr = new XMLHttpRequest();
                        xhr.open('POST', '/upload');
                        xhr.upload.onprogress = function(e) {
                            if (e.lengthComputable) {
                                const p = Math.round(e.loaded * 100 / e.total);
                                bar.style.width = p + '%';
                                percent.textContent = p + '%';
                            }
                        };
                        xhr.onload = function() {
                            if (xhr.status === 200) {
                                setTimeout(function() { window.location.href = '/'; }, 2000);
                            } else {
                                errorMsg.textContent = '上传失败：' + xhr.status + ' ' + (xhr.statusText || '');
                                errorMsg.style.display = 'block';
                            }
                        };
                        xhr.onerror = function() {
                            errorMsg.textContent = '网络错误，请重试';
                            errorMsg.style.display = 'block';
                        };
                        xhr.send(fd);
                        return false;
                    }
                    
                    function validateForm() {
                        return uploadViaXHR();
                    }
                </script>
            </body>
        </html>
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    /// Sends a success response page to the client
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
    
    /// Sends an error response page to the client
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
    
    /// Returns the local IP address of the device
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