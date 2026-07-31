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
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>WiFi 传书 · TextReader</title>
            <style>
                :root {
                    --bg: #F2F2F7; --card: #FFFFFF; --label: #1C1C1E;
                    --secondary: #6E6E73; --separator: rgba(60, 60, 67, 0.18);
                    --fill: rgba(120, 120, 128, 0.08);
                    --tint: #007AFF; --tint-hover: #0071E3;
                    --green: #248A3D; --bar-green: #34C759; --red: #D70015;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg: #000000; --card: #1C1C1E; --label: #F2F2F7;
                        --secondary: #98989E; --separator: rgba(84, 84, 88, 0.65);
                        --fill: rgba(120, 120, 128, 0.16);
                        --tint: #0A84FF; --tint-hover: #409CFF;
                        --green: #30D158; --bar-green: #30D158; --red: #FF453A;
                    }
                }
                * { box-sizing: border-box; }
                body {
                    margin: 0; min-height: 100vh;
                    display: flex; flex-direction: column; align-items: center;
                    padding: 24px 16px 48px;
                    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif;
                    background: var(--bg); color: var(--label);
                    -webkit-font-smoothing: antialiased;
                }
                main { width: 100%; max-width: 440px; }
                header { text-align: center; margin: 28px 0 20px; }
                h1 { margin: 0; font-size: 22px; font-weight: 600; letter-spacing: 0.2px; }
                .subtitle { margin: 6px 0 0; font-size: 14px; color: var(--secondary); }
                .card {
                    background: var(--card); border-radius: 14px; padding: 16px;
                    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06);
                }
                .dropzone {
                    border: 1.5px dashed var(--separator); border-radius: 10px;
                    padding: 36px 16px; text-align: center; cursor: pointer;
                    transition: border-color 0.15s ease, background-color 0.15s ease;
                }
                .dropzone:hover { background: var(--fill); }
                .dropzone:focus-visible { outline: 3px solid var(--tint); outline-offset: 2px; }
                .dropzone.drag-over { border-color: var(--tint); background: var(--fill); }
                .dropzone svg { width: 34px; height: 34px; color: var(--tint); }
                .drop-title { margin: 10px 0 2px; font-size: 15px; font-weight: 500; }
                .drop-hint { margin: 0; font-size: 13px; color: var(--secondary); }
                .file-row {
                    display: flex; align-items: center; gap: 10px;
                    margin-top: 12px; padding: 10px 12px;
                    background: var(--fill); border-radius: 10px;
                }
                .file-meta { flex: 1; min-width: 0; }
                .file-name {
                    display: block; font-size: 14px; font-weight: 500;
                    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
                }
                .file-size { font-size: 12px; color: var(--secondary); }
                .icon-btn {
                    border: none; background: none; padding: 4px;
                    color: var(--secondary); font-size: 18px; line-height: 1;
                    cursor: pointer; border-radius: 6px;
                }
                .icon-btn:focus-visible { outline: 2px solid var(--tint); }
                .progress { margin-top: 12px; }
                .track { height: 4px; background: var(--fill); border-radius: 2px; overflow: hidden; }
                .bar { height: 100%; width: 0%; background: var(--bar-green); transition: width 0.2s ease; }
                .progress-info {
                    display: flex; justify-content: space-between;
                    margin-top: 6px; font-size: 12px; color: var(--secondary);
                }
                .message { margin: 12px 0 0; font-size: 13px; }
                .message.error { color: var(--red); }
                .message.success { color: var(--green); font-weight: 500; }
                .primary {
                    width: 100%; margin-top: 14px; padding: 11px 16px;
                    border: none; border-radius: 10px;
                    background: var(--tint); color: #FFFFFF;
                    font-size: 15px; font-weight: 600; cursor: pointer;
                    transition: background-color 0.15s ease;
                }
                .primary:hover:enabled { background: var(--tint-hover); }
                .primary:disabled { opacity: 0.45; cursor: default; }
                .primary:focus-visible { outline: 3px solid var(--tint); outline-offset: 2px; }
                .footnote { margin-top: 16px; font-size: 12px; color: var(--secondary); text-align: center; }
                @media (prefers-reduced-motion: reduce) {
                    * { transition: none !important; animation: none !important; }
                }
            </style>
        </head>
        <body>
            <main>
                <header>
                    <h1>WiFi 传书</h1>
                    <p class="subtitle">将电脑上的 TXT 文件传入手机书架</p>
                </header>
                <section class="card">
                    <form id="upload-form" action="/upload" method="post" enctype="multipart/form-data">
                        <div id="dropzone" class="dropzone" role="button" tabindex="0" aria-label="拖入或选择 TXT 文件">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"></path>
                                <path d="M14 3v5h5"></path>
                                <path d="M12 17v-5"></path>
                                <path d="M9.5 14.5 12 12l2.5 2.5"></path>
                            </svg>
                            <p class="drop-title">拖入 TXT 文件</p>
                            <p class="drop-hint">或点击从电脑中选择</p>
                        </div>
                        <input type="file" id="file-input" name="book" accept=".txt,text/plain" hidden>
                        <div id="file-row" class="file-row" hidden>
                            <div class="file-meta">
                                <span id="file-name" class="file-name"></span>
                                <span id="file-size" class="file-size"></span>
                            </div>
                            <button type="button" id="clear-btn" class="icon-btn" aria-label="移除文件">&#10005;</button>
                        </div>
                        <div id="progress" class="progress" hidden>
                            <div class="track"><div id="bar" class="bar"></div></div>
                            <div class="progress-info">
                                <span id="status-text">正在上传…</span>
                                <span id="percent">0%</span>
                            </div>
                        </div>
                        <p id="message" class="message" role="status" aria-live="polite" hidden></p>
                        <button type="submit" id="submit-btn" class="primary" disabled>上传到书架</button>
                    </form>
                </section>
                <p class="footnote">传输时请保持手机停留在「WiFi 传输」页面，且与电脑处于同一 WiFi。</p>
            </main>
            <script>
                var dropzone = document.getElementById('dropzone');
                var input = document.getElementById('file-input');
                var fileRow = document.getElementById('file-row');
                var fileNameEl = document.getElementById('file-name');
                var fileSizeEl = document.getElementById('file-size');
                var clearBtn = document.getElementById('clear-btn');
                var progress = document.getElementById('progress');
                var bar = document.getElementById('bar');
                var percent = document.getElementById('percent');
                var statusText = document.getElementById('status-text');
                var message = document.getElementById('message');
                var submitBtn = document.getElementById('submit-btn');
                var form = document.getElementById('upload-form');
                var uploading = false;

                function formatSize(bytes) {
                    if (bytes < 1024) { return bytes + ' B'; }
                    if (bytes < 1048576) { return (bytes / 1024).toFixed(1) + ' KB'; }
                    return (bytes / 1048576).toFixed(1) + ' MB';
                }
                function showMessage(text, type) {
                    message.textContent = text;
                    message.className = 'message ' + type;
                    message.hidden = false;
                }
                function resetToIdle() {
                    input.value = '';
                    fileRow.hidden = true;
                    progress.hidden = true;
                    message.hidden = true;
                    bar.style.width = '0%';
                    percent.textContent = '0%';
                    submitBtn.disabled = true;
                    submitBtn.textContent = '上传到书架';
                    submitBtn.dataset.done = '';
                    uploading = false;
                }
                function setSelectedFile(file) {
                    if (!file) { resetToIdle(); return; }
                    if (!file.name.toLowerCase().endsWith('.txt')) {
                        resetToIdle();
                        showMessage('仅支持 .txt 格式的文本文件', 'error');
                        return;
                    }
                    message.hidden = true;
                    progress.hidden = true;
                    submitBtn.dataset.done = '';
                    fileNameEl.textContent = file.name;
                    fileSizeEl.textContent = formatSize(file.size);
                    fileRow.hidden = false;
                    submitBtn.disabled = false;
                    submitBtn.textContent = '上传到书架';
                }

                dropzone.addEventListener('click', function () { if (!uploading) { input.click(); } });
                dropzone.addEventListener('keydown', function (e) {
                    if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        if (!uploading) { input.click(); }
                    }
                });
                ['dragenter', 'dragover'].forEach(function (evt) {
                    dropzone.addEventListener(evt, function (e) {
                        e.preventDefault();
                        dropzone.classList.add('drag-over');
                    });
                });
                ['dragleave', 'drop'].forEach(function (evt) {
                    dropzone.addEventListener(evt, function (e) {
                        e.preventDefault();
                        dropzone.classList.remove('drag-over');
                    });
                });
                dropzone.addEventListener('drop', function (e) {
                    if (uploading) { return; }
                    if (e.dataTransfer.files.length > 0) {
                        input.files = e.dataTransfer.files;
                        setSelectedFile(input.files[0]);
                    }
                });
                input.addEventListener('change', function () { setSelectedFile(input.files[0]); });
                clearBtn.addEventListener('click', function () { if (!uploading) { resetToIdle(); } });

                form.addEventListener('submit', function (e) {
                    e.preventDefault();
                    if (uploading) { return; }
                    if (submitBtn.dataset.done === '1') { resetToIdle(); return; }
                    var file = input.files[0];
                    if (!file) { showMessage('请先选择一个 TXT 文件', 'error'); return; }

                    uploading = true;
                    submitBtn.disabled = true;
                    clearBtn.disabled = true;
                    message.hidden = true;
                    progress.hidden = false;
                    statusText.textContent = '正在上传…';
                    bar.style.width = '0%';
                    percent.textContent = '0%';

                    var fd = new FormData();
                    fd.append('book', file, file.name);
                    var xhr = new XMLHttpRequest();
                    xhr.open('POST', '/upload');
                    xhr.upload.onprogress = function (e2) {
                        if (e2.lengthComputable) {
                            var p = Math.round(e2.loaded * 100 / e2.total);
                            bar.style.width = p + '%';
                            percent.textContent = p + '%';
                        }
                    };
                    xhr.onload = function () {
                        uploading = false;
                        clearBtn.disabled = false;
                        if (xhr.status === 200) {
                            bar.style.width = '100%';
                            percent.textContent = '100%';
                            statusText.textContent = '已完成';
                            showMessage('「' + file.name + '」已加入书架', 'success');
                            submitBtn.dataset.done = '1';
                            submitBtn.textContent = '再传一本';
                            submitBtn.disabled = false;
                        } else {
                            statusText.textContent = '上传失败';
                            showMessage('上传失败（' + xhr.status + '），请重试', 'error');
                            submitBtn.textContent = '重试';
                            submitBtn.disabled = false;
                        }
                    };
                    xhr.onerror = function () {
                        uploading = false;
                        clearBtn.disabled = false;
                        statusText.textContent = '连接中断';
                        showMessage('网络连接中断，请确认手机仍停留在传输页面后重试', 'error');
                        submitBtn.textContent = '重试';
                        submitBtn.disabled = false;
                    };
                    xhr.send(fd);
                });
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
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>上传成功 · WiFi 传书</title>
            <style>
                :root { --bg: #F2F2F7; --card: #FFFFFF; --label: #1C1C1E; --secondary: #6E6E73; --tint: #007AFF; --green: #248A3D; }
                @media (prefers-color-scheme: dark) {
                    :root { --bg: #000000; --card: #1C1C1E; --label: #F2F2F7; --secondary: #98989E; --tint: #0A84FF; --green: #30D158; }
                }
                body {
                    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
                    background: var(--bg); color: var(--label);
                }
                .card {
                    background: var(--card); border-radius: 14px; padding: 32px 24px;
                    width: 100%; max-width: 360px; text-align: center;
                    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06); box-sizing: border-box;
                }
                .icon { font-size: 40px; color: var(--green); }
                h1 { font-size: 20px; margin: 12px 0 6px; }
                .detail { margin: 0; font-size: 14px; color: var(--secondary); overflow-wrap: anywhere; }
                .primary {
                    display: inline-block; margin-top: 20px; padding: 10px 20px; border-radius: 10px;
                    background: var(--tint); color: #FFFFFF; text-decoration: none; font-size: 15px; font-weight: 600;
                }
            </style>
        </head>
        <body>
            <main class="card">
                <div class="icon" aria-hidden="true">✓</div>
                <h1>上传成功</h1>
                <p class="detail">「\(filename)」已加入书架</p>
                <a href="/" class="primary">继续传书</a>
            </main>
            <script>setTimeout(function () { window.location.href = '/'; }, 2000);</script>
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
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>上传失败 · WiFi 传书</title>
            <style>
                :root { --bg: #F2F2F7; --card: #FFFFFF; --label: #1C1C1E; --secondary: #6E6E73; --tint: #007AFF; --red: #D70015; }
                @media (prefers-color-scheme: dark) {
                    :root { --bg: #000000; --card: #1C1C1E; --label: #F2F2F7; --secondary: #98989E; --tint: #0A84FF; --red: #FF453A; }
                }
                body {
                    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
                    background: var(--bg); color: var(--label);
                }
                .card {
                    background: var(--card); border-radius: 14px; padding: 32px 24px;
                    width: 100%; max-width: 360px; text-align: center;
                    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.06); box-sizing: border-box;
                }
                .icon { font-size: 40px; color: var(--red); }
                h1 { font-size: 20px; margin: 12px 0 6px; }
                .detail { margin: 0; font-size: 14px; color: var(--secondary); overflow-wrap: anywhere; }
                .primary {
                    display: inline-block; margin-top: 20px; padding: 10px 20px; border-radius: 10px;
                    background: var(--tint); color: #FFFFFF; text-decoration: none; font-size: 15px; font-weight: 600;
                }
            </style>
        </head>
        <body>
            <main class="card">
                <div class="icon" aria-hidden="true">✕</div>
                <h1>上传失败</h1>
                <p class="detail">\(message)</p>
                <a href="/" class="primary">返回重试</a>
            </main>
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
