import Network
import Foundation

class WiFiTransferService: ObservableObject, @unchecked Sendable {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var serverAddress: String?
    
    struct UploadState {
        var fileName: String?
        var receivedBytes: Int
        var totalBytes: Int?
        var startedAt: Date
        var isCompleted: Bool
        var errorMessage: String?
    }
    
    @Published var uploadState: UploadState?
    var onFileReceived: ((String, String) -> Void)?
    
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
                self.receiveData(on: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func receiveData(on connection: NWConnection) {
        var buffer = Data()

        func receiveHeaders() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if error != nil {
                    connection.cancel()
                    return
                }

                if let data {
                    buffer.append(data)
                }

                if let head = WiFiUploadRequestParser.parseHead(from: buffer) {
                    if head.method == "OPTIONS" {
                        self.sendOptionsPreflight(on: connection)
                    } else if head.method == "POST", head.path == "/upload" {
                        guard head.multipartBoundary != nil else {
                            self.sendErrorResponse(on: connection, message: "无法找到 multipart boundary")
                            return
                        }
                        guard head.contentLength != nil else {
                            self.sendErrorResponse(on: connection, message: "请求缺少 Content-Length")
                            return
                        }
                        self.receiveFileUpload(connection: connection, initialData: buffer, head: head)
                    } else {
                        self.sendUploadForm(on: connection)
                    }
                    return
                }

                if buffer.count > 65_536 {
                    self.sendErrorResponse(on: connection, message: "请求头过大")
                } else if isComplete {
                    self.sendErrorResponse(on: connection, message: "请求头不完整")
                } else {
                    receiveHeaders()
                }
            }
        }

        receiveHeaders()
    }
    
    private func receiveFileUpload(
        connection: NWConnection,
        initialData: Data,
        head: WiFiUploadRequestParser.RequestHead
    ) {
        var buffer = initialData
        let startTime = Date()
        let totalBytes = head.contentLength
        var detectedFileName = WiFiUploadRequestParser.fileNameIfAvailable(in: buffer, head: head)

        func publishProgress() {
            let receivedBytes = WiFiUploadRequestParser.receivedBodyByteCount(in: buffer, head: head)
            DispatchQueue.main.async { [weak self] in
                self?.uploadState = UploadState(
                    fileName: detectedFileName,
                    receivedBytes: min(receivedBytes, totalBytes ?? receivedBytes),
                    totalBytes: totalBytes,
                    startedAt: startTime,
                    isCompleted: false,
                    errorMessage: nil
                )
            }
        }

        func publishConnectionError() {
            DispatchQueue.main.async { [weak self] in
                self?.uploadState = UploadState(
                    fileName: detectedFileName,
                    receivedBytes: WiFiUploadRequestParser.receivedBodyByteCount(in: buffer, head: head),
                    totalBytes: totalBytes,
                    startedAt: startTime,
                    isCompleted: false,
                    errorMessage: "接收数据时发生错误"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.uploadState = nil
                }
            }
        }

        @discardableResult
        func processIfComplete() -> Bool {
            if detectedFileName == nil {
                detectedFileName = WiFiUploadRequestParser.fileNameIfAvailable(in: buffer, head: head)
            }
            publishProgress()

            guard let requestData = WiFiUploadRequestParser.completeRequestData(from: buffer, head: head) else {
                return false
            }
            self.processReceivedData(buffer: requestData, head: head, connection: connection)
            return true
        }

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if error != nil {
                    publishConnectionError()
                    connection.cancel()
                    return
                }

                if let data {
                    buffer.append(data)
                }

                if processIfComplete() {
                    return
                }

                if isComplete {
                    self.sendErrorResponse(on: connection, message: "文件数据接收不完整")
                } else {
                    receive()
                }
            }
        }

        if processIfComplete() {
            return
        }
        receive()
    }
    
    private func processReceivedData(
        buffer: Data,
        head: WiFiUploadRequestParser.RequestHead,
        connection: NWConnection
    ) {
        do {
            let upload = try WiFiUploadRequestParser.parseUpload(from: buffer, head: head)
            DispatchQueue.main.async { [weak self] in
                self?.onFileReceived?(upload.fileName, upload.content)
                if var state = self?.uploadState {
                    state.fileName = upload.fileName
                    state.receivedBytes = state.totalBytes ?? state.receivedBytes
                    state.isCompleted = true
                    state.errorMessage = nil
                    self?.uploadState = state
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.uploadState = nil
                }
            }
            sendSuccessResponse(on: connection, filename: upload.fileName)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "文件格式解析失败"
            sendErrorResponse(on: connection, message: message)
            DispatchQueue.main.async { [weak self] in
                if var state = self?.uploadState {
                    state.errorMessage = message
                    state.isCompleted = false
                    self?.uploadState = state
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.uploadState = nil
                }
            }
        }
    }

    private func sendOptionsPreflight(on connection: NWConnection) {
        let resp = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        """
        sendHTTPResponse(resp, on: connection)
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
                        padding: 40px 20px;
                        margin: 20px 0;
                        transition: border-color 0.2s, background-color 0.2s;
                    }
                    .upload-form.drag-over {
                        border-color: #007AFF;
                        background-color: rgba(0, 122, 255, 0.05);
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
                        <label class="file-label">拖入 TXT 文件，或点击选择</label>
                        <input type="file" name="book" accept=".txt" class="file-input" id="file-input" onchange="updateFileName()">
                        <button type="button" class="upload-button" onclick="document.getElementById('file-input').click()">
                            选择文件
                        </button>
                        <div id="selected-file"></div>
                        <div class="error" id="error-message">仅支持 .txt 格式的文本文件</div>
                        <button type="submit" class="upload-button" style="margin-top: 10px;">上传</button>
                        <div id="progress">
                            <div class="bar-wrap"><div id="bar" class="bar"></div></div>
                            <div id="percent" class="percent">0%</div>
                        </div>
                    </form>
                </div>
                <script>
                    const dropZone = document.querySelector('.upload-form');
                    const fileInput = document.getElementById('file-input');

                    ['dragenter', 'dragover'].forEach(evt => {
                        dropZone.addEventListener(evt, function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            dropZone.classList.add('drag-over');
                        });
                    });
                    ['dragleave', 'drop'].forEach(evt => {
                        dropZone.addEventListener(evt, function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            dropZone.classList.remove('drag-over');
                        });
                    });
                    dropZone.addEventListener('drop', function(e) {
                        const files = e.dataTransfer.files;
                        if (files.length > 0) {
                            fileInput.files = files;
                            updateFileName();
                        }
                    });

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
                            errorMsg.textContent = '网络连接中断，请重试';
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
        sendHTTPResponse(response, on: connection)
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
                <h1>上传成功</h1>
                <p class="file-name">文件名：\(filename)</p>
                <div class="progress">
                    <div class="progress-bar"></div>
                </div>
                <p>即将返回…</p>
                <script>setTimeout(function() { window.location.href = '/'; }, 2000);</script>
            </body>
        </html>
        """
        sendHTTPResponse(successResponse, on: connection)
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
        sendHTTPResponse(errorResponse, on: connection)
    }

    private func sendHTTPResponse(_ response: String, on connection: NWConnection) {
        guard let originalData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }

        let delimiter = Data("\r\n\r\n".utf8)
        var responseData = originalData
        if let headerRange = originalData.range(of: delimiter) {
            let headerData = originalData.subdata(in: 0..<headerRange.lowerBound)
            let bodyData = originalData.subdata(in: headerRange.upperBound..<originalData.endIndex)
            let header = String(decoding: headerData, as: UTF8.self)
            if !header.lowercased().contains("\r\ncontent-length:") {
                responseData = Data("\(header)\r\nContent-Length: \(bodyData.count)\r\n\r\n".utf8)
                responseData.append(bodyData)
            }
        }

        connection.send(
            content: responseData,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
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
