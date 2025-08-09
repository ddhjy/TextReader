import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "导入到TextReader"
        self.placeholder = "添加备注（可选）"
    }
    
    override func isContentValid() -> Bool {
        // 始终允许用户进行分享，无论内容如何
        return true
    }
    
    override func didSelectPost() {
        let alert = UIAlertController(title: "处理中", message: "正在提取文本内容...", preferredStyle: .alert)
        present(alert, animated: true)
        
        processSharedItems { success in
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    if success {
                        let successAlert = UIAlertController(title: "成功", message: "文本已成功导入到TextReader", preferredStyle: .alert)
                        successAlert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in
                            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        }))
                        self.present(successAlert, animated: true)
                    } else {
                        let failureAlert = UIAlertController(title: "失败", message: "无法提取有效的文本内容", preferredStyle: .alert)
                        failureAlert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in
                            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        }))
                        self.present(failureAlert, animated: true)
                    }
                }
            }
        }
    }
    
    override func configurationItems() -> [Any]! {
        // 自定义分享面板的配置项
        return []
    }
    
    // MARK: - 内容处理方法
    
    private func processSharedItems(completion: @escaping (Bool) -> Void) {
        guard let extensionContext = self.extensionContext else {
            completion(false)
            return
        }
        
        guard let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completion(false)
            return
        }
        
        var extractedText = ""
        
        if !contentText.isEmpty {
            extractedText += contentText
            extractedText += "\n\n"
        }
        
        let dispatchGroup = DispatchGroup()
        
        var extractionSuccess = false
        
        for inputItem in inputItems {
            guard let attachments = inputItem.attachments else { continue }
            
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    dispatchGroup.enter()
                    
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (data, error) in
                        defer { dispatchGroup.leave() }
                        
                        if let error = error {
                            print("加载文本出错: \(error.localizedDescription)")
                            return
                        }
                        
                        if let text = data as? String {
                            extractedText += text
                            extractionSuccess = true
                        } else if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                            extractedText += text
                            extractionSuccess = true
                        }
                    }
                }
                else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    dispatchGroup.enter()
                    
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (data, error) in
                        defer { dispatchGroup.leave() }
                        
                        if let error = error {
                            print("加载URL出错: \(error.localizedDescription)")
                            return
                        }
                        
                        if let url = data as? URL {
                            let urlString = url.absoluteString
                            extractedText += "来源网址: \(urlString)\n\n"
                            extractionSuccess = true
                        }
                    }
                }
                else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    dispatchGroup.enter()
                    
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                        defer { dispatchGroup.leave() }
                        
                        if let error = error {
                            print("加载文件URL出错: \(error.localizedDescription)")
                            return
                        }
                        
                        if let fileURL = data as? URL {
                            if fileURL.pathExtension.lowercased() == "txt" {
                                do {
                                    let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                                    extractedText += fileContent
                                    extractionSuccess = true
                                } catch {
                                    print("读取文件内容出错: \(error.localizedDescription)")
                                    
                                    do {
                                        let gb18030Encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
                                        let fileContent = try String(contentsOf: fileURL, encoding: gb18030Encoding)
                                        extractedText += fileContent
                                        extractionSuccess = true
                                    } catch {
                                        print("尝试GB18030编码读取文件内容出错: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if !extractedText.isEmpty && extractionSuccess {
                self.openMainAppWithText(extractedText)
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    private func openMainAppWithText(_ text: String) {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("无法对文本进行URL编码")
            return
        }
        
        let urlString = "textreader://import?text=\(encodedText)"
        
        if let url = URL(string: urlString) {
            self.extensionContext?.open(url, completionHandler: { success in
                if success {
                    print("成功打开URL: \(urlString)")
                } else {
                    print("无法打开URL: \(urlString)")
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            })
        }
    }
    
    enum TextEncodingType {
        case utf8
        case gb18030
        
        var encoding: String.Encoding {
            switch self {
            case .utf8:
                return .utf8
            case .gb18030:
                return .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            }
        }
    }
}
