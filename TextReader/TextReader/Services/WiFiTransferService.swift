import Network
import Foundation

class WiFiTransferService: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case stopped
        case starting
        /// 正在接收；`address` 是要在电脑浏览器里打开的地址。
        case ready(address: String)
        /// 已经在监听，但手机没有连上 Wi‑Fi，电脑访问不到。
        case noWiFi
        case failed(String)
    }

    /// 一次传输的结果。传完之后一直留在页面上，直到下次重新进入传书页面。
    struct TransferRecord: Identifiable, Equatable {
        let id: UUID
        let fileName: String
        let succeeded: Bool
        let detail: String
        let date: Date
    }

    /// 外部保存收到的文件之后返回的结果，决定回给电脑的内容和记在列表里的那一行。
    enum ReceiveResult {
        /// `conflictingTitle`：书架里已有同名的书时，原本想用的书名；这时新书已另存为 `title`。
        case saved(title: String, conflictingTitle: String?)
        case rejected(reason: String)
    }
    
    struct UploadState {
        var fileName: String?
        var receivedBytes: Int
        var totalBytes: Int?
        var startedAt: Date
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var records: [TransferRecord] = []
    @Published private(set) var uploadState: UploadState?

    /// 在主线程上同步调用：保存成功与否要立刻回给电脑上的网页。
    var onFileReceived: ((_ fileName: String, _ content: String) -> ReceiveResult)?

    /// 8080 被别的 App 占用时依次往后试，界面上显示的是实际用上的端口。
    private static let candidatePorts: [UInt16] = Array(8080...8089)

    private var listener: NWListener?
    private var listenerIsReady = false
    private var activePort: UInt16?
    private var pathMonitor: NWPathMonitor?

    deinit {
        listener?.cancel()
        pathMonitor?.cancel()
    }
    
    func startServer() {
        guard listener == nil else { return }

        status = .starting
        startListening(candidateIndex: 0)
        startPathMonitorIfNeeded()
    }
    
    func stopServer() {
        pathMonitor?.cancel()
        pathMonitor = nil
        listener?.cancel()
        listener = nil
        listenerIsReady = false
        activePort = nil
        uploadState = nil
        status = .stopped
    }

    func clearRecords() {
        records = []
    }

    private func startListening(candidateIndex: Int) {
        guard candidateIndex < Self.candidatePorts.count else {
            status = .failed("无法开始接收，请稍后重试")
            return
        }

        let port = Self.candidatePorts[candidateIndex]
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let newListener = try? NWListener(using: .tcp, on: endpointPort) else {
            startListening(candidateIndex: candidateIndex + 1)
            return
        }

        listener = newListener
        listenerIsReady = false
        activePort = port

        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            // 只理会当前这个监听器的状态；已经被换掉或停掉的监听器晚到的回调一律忽略。
            guard let self, let newListener, self.listener === newListener else { return }

            switch state {
            case .ready:
                self.listenerIsReady = true
                self.refreshAddress()
            case .waiting:
                self.listenerIsReady = false
                self.status = .noWiFi
            case .failed(let error):
                // 失败的监听器必须清掉，否则之后再点「重试」永远不会重新监听。
                newListener.cancel()
                self.listener = nil
                self.listenerIsReady = false
                self.activePort = nil

                if Self.isAddressInUse(error) {
                    self.startListening(candidateIndex: candidateIndex + 1)
                } else {
                    self.status = .failed("无法开始接收，请重试")
                }
            default:
                break
            }
        }
        
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        newListener.start(queue: .main)
    }

    private static func isAddressInUse(_ error: NWError) -> Bool {
        if case .posix(let code) = error {
            return code == .EADDRINUSE
        }
        return false
    }

    private func startPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            // 连上 / 断开 Wi‑Fi、换了网络之后地址会变，页面上显示的要跟着变。
            self?.refreshAddress()
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func refreshAddress() {
        guard listener != nil, listenerIsReady, let port = activePort else { return }

        let newStatus: Status
        if let ipAddress = getLocalIPAddress() {
            newStatus = .ready(address: "http://\(ipAddress):\(port)")
        } else {
            newStatus = .noWiFi
        }

        if status != newStatus {
            status = newStatus
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveData(on: connection)
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
            uploadState = UploadState(
                fileName: detectedFileName,
                receivedBytes: min(receivedBytes, totalBytes ?? receivedBytes),
                totalBytes: totalBytes,
                startedAt: startTime
            )
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
            self.processReceivedData(
                buffer: requestData,
                head: head,
                connection: connection,
                fallbackFileName: detectedFileName
            )
            return true
        }

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if error != nil {
                    self.finishUpload(
                        fileName: detectedFileName,
                        succeeded: false,
                        detail: "接收中断，请在电脑上重新上传"
                    )
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
                    let message = "文件没有传完，请在电脑上重新上传"
                    self.finishUpload(fileName: detectedFileName, succeeded: false, detail: message)
                    self.sendErrorResponse(on: connection, message: message)
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
        connection: NWConnection,
        fallbackFileName: String?
    ) {
        do {
            let upload = try WiFiUploadRequestParser.parseUpload(from: buffer, head: head)
            let result = onFileReceived?(upload.fileName, upload.content)
                ?? .rejected(reason: "暂时无法保存，请重试")

            switch result {
            case .saved(let title, let conflictingTitle):
                if let conflictingTitle {
                    finishUpload(
                        fileName: title,
                        succeeded: true,
                        detail: "书架里已有《\(conflictingTitle)》，已另存为这个名字"
                    )
                    sendSuccessResponse(
                        on: connection,
                        message: "书架里已有《\(conflictingTitle)》，新传的已另存为《\(title)》"
                    )
                } else {
                    finishUpload(fileName: title, succeeded: true, detail: "已加入书架")
                    sendSuccessResponse(on: connection, message: "《\(title)》已加入书架")
                }
            case .rejected(let reason):
                finishUpload(fileName: upload.fileName, succeeded: false, detail: reason)
                sendErrorResponse(on: connection, message: reason)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "文件格式解析失败"
            finishUpload(fileName: fallbackFileName, succeeded: false, detail: message)
            sendErrorResponse(on: connection, message: message)
        }
    }

    private func finishUpload(fileName: String?, succeeded: Bool, detail: String) {
        uploadState = nil
        records.insert(
            TransferRecord(
                id: UUID(),
                fileName: fileName.nilIfEmpty() ?? "未知文件",
                succeeded: succeeded,
                detail: detail,
                date: Date()
            ),
            at: 0
        )
    }

    /// 网页里的脚本从 `X-Upload-Message` 响应头读结果文字。HTTP 头只能放 ASCII，所以整句做百分号编码。
    static func headerEncoded(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func htmlEscaped(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
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
        Cache-Control: no-store\r
        Connection: close\r
        \r
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>Wi‑Fi 传书 · 随心读</title>
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
                .message { margin: 12px 0 0; font-size: 13px; overflow-wrap: anywhere; }
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
                    <h1>Wi‑Fi 传书</h1>
                    <p class="subtitle">把电脑上的 TXT 或 MD 文件传到手机书架</p>
                </header>
                <section class="card">
                    <form id="upload-form" action="/upload" method="post" enctype="multipart/form-data">
                        <div id="dropzone" class="dropzone" role="button" tabindex="0" aria-label="拖入或选择 TXT、MD 文件">
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                                <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"></path>
                                <path d="M14 3v5h5"></path>
                                <path d="M12 17v-5"></path>
                                <path d="M9.5 14.5 12 12l2.5 2.5"></path>
                            </svg>
                            <p class="drop-title">拖入 TXT 或 MD 文件</p>
                            <p class="drop-hint">或点击从电脑中选择</p>
                        </div>
                        <input type="file" id="file-input" name="book" accept=".txt,.md,text/plain,text/markdown" hidden>
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
                <p class="footnote">传输时请保持手机停留在「Wi‑Fi 传书」页面，且与电脑处于同一 Wi‑Fi。</p>
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
                function serverMessage(xhr) {
                    try {
                        return decodeURIComponent(xhr.getResponseHeader('X-Upload-Message') || '');
                    } catch (err) {
                        return '';
                    }
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
                    var lowerName = file.name.toLowerCase();
                    if (!lowerName.endsWith('.txt') && !lowerName.endsWith('.md')) {
                        resetToIdle();
                        showMessage('只能传 .txt 或 .md 文本文件', 'error');
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
                    if (!file) { showMessage('请先选择一个 TXT 或 MD 文件', 'error'); return; }

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
                            showMessage(serverMessage(xhr) || ('「' + file.name + '」已加入书架'), 'success');
                            submitBtn.dataset.done = '1';
                            submitBtn.textContent = '再传一本';
                            submitBtn.disabled = false;
                        } else {
                            statusText.textContent = '上传失败';
                            showMessage(serverMessage(xhr) || ('上传失败（' + xhr.status + '），请重试'), 'error');
                            submitBtn.textContent = '重试';
                            submitBtn.disabled = false;
                        }
                    };
                    xhr.onerror = function () {
                        uploading = false;
                        clearBtn.disabled = false;
                        statusText.textContent = '连接中断';
                        showMessage('连接中断了。请确认手机还停在「Wi‑Fi 传书」页面，然后重试', 'error');
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
    
    private func sendSuccessResponse(on connection: NWConnection, message: String) {
        let successResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        X-Upload-Message: \(Self.headerEncoded(message))\r
        Connection: close\r
        \r
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>上传成功 · Wi‑Fi 传书</title>
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
                <p class="detail">\(Self.htmlEscaped(message))</p>
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
        X-Upload-Message: \(Self.headerEncoded(message))\r
        Connection: close\r
        \r
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>上传失败 · Wi‑Fi 传书</title>
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
                <p class="detail">\(Self.htmlEscaped(message))</p>
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
    
    /// 电脑能访问到的本机地址：优先 Wi‑Fi（en0），其次是手机开热点时的桥接口，最后是其他有线 / 无线网口。
    func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var wifiAddress: String?
        var hotspotAddress: String?
        var otherAddress: String?
        
        var ptr = ifaddr
        while let current = ptr {
            let interface = current.pointee
            ptr = interface.ifa_next

            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress,
                              socklen_t(socketAddress.pointee.sa_len),
                              &hostname,
                              socklen_t(hostname.count),
                              nil,
                              0,
                              NI_NUMERICHOST) == 0 else {
                continue
            }

            let address = String(cString: hostname)
            // 169.254.x.x 是没拿到路由器分配地址时的自动地址，电脑通常访问不到。
            guard !address.isEmpty, !address.hasPrefix("169.254.") else { continue }

            if name == "en0" {
                wifiAddress = address
            } else if name.hasPrefix("bridge") {
                hotspotAddress = hotspotAddress ?? address
            } else if name.hasPrefix("en") {
                otherAddress = otherAddress ?? address
            }
        }

        return wifiAddress ?? hotspotAddress ?? otherAddress
    }
} 
