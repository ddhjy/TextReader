import Social
import UIKit
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    private let sharedImportStore = SharedImportStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "导入到读书"
        placeholder = "标题（可选）"
    }

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        let progressAlert = UIAlertController(title: "正在导入", message: "正在处理分享内容…", preferredStyle: .alert)
        present(progressAlert, animated: true)

        processSharedItems { success in
            DispatchQueue.main.async {
                progressAlert.dismiss(animated: true) {
                    if success {
                        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    } else {
                        let failureAlert = UIAlertController(
                            title: "导入失败",
                            message: "仅支持分享纯文本或 `.txt` / `.md` 文件",
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
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private func processSharedItems(completion: @escaping (Bool) -> Void) {
        guard let extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completion(false)
            return
        }

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
                completion(false)
                return
            }

            let preferredTitle = self.preferredImportTitle(fileTitles: fileTitles)

            do {
                try self.sharedImportStore.enqueueTextImport(
                    text: combinedText,
                    title: preferredTitle,
                    sourceType: sourceType
                )
                completion(true)
            } catch {
                print("[ShareViewController] 写入共享导入失败: \(error)")
                completion(false)
            }
        }
    }

    private func preferredImportTitle(fileTitles: [String]) -> String? {
        let trimmedUserTitle = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserTitle.isEmpty {
            return trimmedUserTitle
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
