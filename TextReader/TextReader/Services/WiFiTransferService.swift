import Network
import Foundation

class WiFiTransferService: ObservableObject {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var serverAddress: String?
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
            if let error = error {
                return
            }
            
            if let data = data, let request = String(data: data, encoding: .utf8) {
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
        
        // A timer to detect when the upload has finished
        var lastReceiveTime = Date()
        var noDataTimer: Timer?
        
        func checkDataComplete() {
            // If no new data received for 3 seconds, consider the transfer complete
            if Date().timeIntervalSince(lastReceiveTime) >= 3.0 {
                processReceivedData()
                noDataTimer?.invalidate()
                noDataTimer = nil
            }
        }
        
        func processReceivedData() {
            // Try to detect file encoding
            let encodings: [String.Encoding] = [.utf8]
            var fileContent: String?
            
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
                        
                        let boundaryEnd = "\(boundary)--"
                        if let contentStart = content.range(of: "\r\n\r\n", range: headerEnd.upperBound..<content.endIndex),
                           let contentEnd = content.range(of: boundaryEnd) {
                            let fileContent = String(content[contentStart.upperBound..<contentEnd.lowerBound])
                            
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
                sendErrorResponse(on: connection, message: "不支持的文件编码格式")
            }
        }
        
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
                if let error = error {
                    self?.sendErrorResponse(on: connection, message: "接收数据时发生错误")
                    return
                }
                
                if let data = data {
                    buffer.append(data)
                    lastReceiveTime = Date()
                    
                    // Reset timer
                    noDataTimer?.invalidate()
                    noDataTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        checkDataComplete()
                    }
                }
                
                if isComplete {
                    noDataTimer?.invalidate()
                    processReceivedData()
                } else if error == nil {
                    receive()
                }
            }
        }
        
        // Start initial timer
        noDataTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            checkDataComplete()
        }
        
        receive()
    }
    
    /// Processes HTTP requests and responds appropriately
    private func processRequest(_ request: String, on connection: NWConnection) {
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