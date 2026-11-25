import Social
import UIKit
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    private let sharedImportStore = SharedImportStore()

    /// 书名最多取这么多字，再长的多半不是书名而是一段正文。
    private static let maxTitleLength = 60

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "导入到随心读"
        placeholder = "书名（可不填）"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 系统默认把右上角的按钮叫「发布」，这里做的事是导入。
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "导入"
    }

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        let progressAlert = UIAlertController(title: "正在导入", message: "正在处理分享内容…", preferredStyle: .alert)
        present(progressAlert, animated: true)

        processSharedItems { failureMessage in
            DispatchQueue.main.async {
                progressAlert.dismiss(animated: true) {
                    guard let failureMessage else {
                        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        return
                    }

                    let failureAlert = UIAlertController(
                        title: "没有导入",
                        message: failureMessage,
                        preferredStyle: .alert
                    )
                    failureAlert.addAction(UIAlertAction(title: "好", style: .default) { _ in
                        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    })
                    self.present(failureAlert, animated: true)
                }
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private static let nothingToImportMessage = "没有找到能导入的文字。可以分享一段文字，或 TXT、MD 文件。"
    private static let saveFailedMessage = "内容没能存下来，请再试一次。"

    /// - Parameter completion: 成功时传 nil；失败时传要告诉用户的原因。
    private func processSharedItems(completion: @escaping (String?) -> Void) {
        guard let extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completion(Self.nothingToImportMessage)
            return
        }

        // 输入框的内容要在主线程上读，后面的处理都在后台。
        let typedText = contentText ?? ""

        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        var extractedSegments: [String] = []
        var fileTitles: [String] = []
        var sourceType: SharedImportSourceType = .text
        var extractionSucceeded = false

        for inputItem in inputItems {
            guard let attachments = inputItem.attachments else { continue }

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    dispatchGroup.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                        defer { dispatchGroup.leave() }

                        if let error {
                            print("[ShareViewController] 加载文件 URL 失败: \(error.localizedDescription)")
                            return
                        }

                        guard let fileURL = self.extractFileURL(from: item),
                              self.isSupportedTextFile(fileURL) else {
                            return
                        }

                        guard let fileText = self.readTextFile(at: fileURL) else {
                            print("[ShareViewController] 读取文本文件失败: \(String(describing: self.extractFileURL(from: item)?.lastPathComponent))")
                            return
                        }

                        lock.lock()
                        extractedSegments.append(fileText)
                        fileTitles.append(fileURL.deletingPathExtension().lastPathComponent)
                        sourceType = .file
                        extractionSucceeded = true
                        lock.unlock()
                    }
                    continue
                }

                guard let textTypeIdentifier = preferredTextTypeIdentifier(for: attachment) else {
                    continue
                }

                dispatchGroup.enter()
                attachment.loadItem(forTypeIdentifier: textTypeIdentifier, options: nil) { item, error in
                    defer { dispatchGroup.leave() }

                    if let error {
                        print("[ShareViewController] 加载文本失败: \(error.localizedDescription)")
                        return
                    }

                    guard let text = self.extractText(from: item),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }

                    lock.lock()
                    extractedSegments.append(text)
                    extractionSucceeded = true
                    lock.unlock()
                }
            }
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            let combinedText = extractedSegments
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            guard extractionSucceeded, !combinedText.isEmpty else {
                completion(Self.nothingToImportMessage)
                return
            }

            let preferredTitle = Self.preferredImportTitle(
                typedText: typedText,
                sharedText: combinedText,
                fileTitles: fileTitles
            )

            do {
                try self.sharedImportStore.enqueueTextImport(
                    text: combinedText,
                    title: preferredTitle,
                    sourceType: sourceType
                )
                completion(nil)
            } catch {
                print("[ShareViewController] 写入共享导入失败: \(error)")
                completion(Self.saveFailedMessage)
            }
        }
    }

    /// - Parameters:
    ///   - typedText: 分享面板输入框里的文字。
    ///   - sharedText: 被分享过来的正文。
    private static func preferredImportTitle(typedText: String,
                                             sharedText: String,
                                             fileTitles: [String]) -> String? {
        let trimmedTypedText = typedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 分享一段文字时，系统会把这段文字原样填进输入框。那是正文，不是用户起的书名；
        // 这种情况不指定书名，交给 App 用正文第一行来命名。
        if !trimmedTypedText.isEmpty, trimmedTypedText != sharedText {
            let firstLine = trimmedTypedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            if let firstLine {
                return String(firstLine.prefix(maxTitleLength))
            }
        }

        guard fileTitles.count == 1 else { return nil }
        return fileTitles[0]
    }

    private func preferredTextTypeIdentifier(for attachment: NSItemProvider) -> String? {
        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return UTType.plainText.identifier
        }

        if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            return UTType.text.identifier
        }

        return nil
    }

    private func extractText(from item: NSSecureCoding?) -> String? {
        if let text = item as? String {
            return text
        }

        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }

        if let url = item as? URL,
           isSupportedTextFile(url) {
            return readTextFile(at: url)
        }

        return nil
    }

    private func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let nsURL = item as? NSURL {
            return nsURL as URL
        }

        return nil
    }

    private func isSupportedTextFile(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "txt" || pathExtension == "md"
    }

    private func readTextFile(at url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            do {
                return try String(contentsOf: url, encoding: .gb_18030_2000)
            } catch {
                return nil
            }
        }
    }
}

private extension String.Encoding {
    static let gb_18030_2000 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
}
