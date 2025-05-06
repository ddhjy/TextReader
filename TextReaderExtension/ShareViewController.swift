//
//  ShareViewController.swift
//  TextReaderExtension
//
//  Created by zengkai on 2025/5/6.
//

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
        // 显示加载指示器
        let alert = UIAlertController(title: "处理中", message: "正在提取文本内容...", preferredStyle: .alert)
        present(alert, animated: true)
        
        // 开始处理分享内容
        processSharedItems { success in
            // 在主线程更新UI
            DispatchQueue.main.async {
                // 关闭加载指示器
                alert.dismiss(animated: true) {
                    if success {
                        // 成功处理
                        let successAlert = UIAlertController(title: "成功", message: "文本已成功导入到TextReader", preferredStyle: .alert)
                        successAlert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in
                            // 关闭分享扩展
                            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        }))
                        self.present(successAlert, animated: true)
                    } else {
                        // 处理失败
                        let failureAlert = UIAlertController(title: "失败", message: "无法提取有效的文本内容", preferredStyle: .alert)
                        failureAlert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in
                            // 关闭分享扩展
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
        
        // 获取所有输入项
        guard let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completion(false)
            return
        }
        
        // 组合所有提取的文本
        var extractedText = ""
        
        // 如果有来自分享面板的文本，加入
        if !contentText.isEmpty {
            extractedText += contentText
            extractedText += "\n\n"
        }
        
        // 创建一个分发组，用于异步处理所有共享项
        let dispatchGroup = DispatchGroup()
        
        // 跟踪是否成功提取了文本
        var extractionSuccess = false
        
        // 遍历所有输入项
        for inputItem in inputItems {
            guard let attachments = inputItem.attachments else { continue }
            
            for attachment in attachments {
                // 检查是否是文本内容
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
                // 检查是否是URL（网页）
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
                // 检查是否是文件
                else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    dispatchGroup.enter()
                    
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                        defer { dispatchGroup.leave() }
                        
                        if let error = error {
                            print("加载文件URL出错: \(error.localizedDescription)")
                            return
                        }
                        
                        if let fileURL = data as? URL {
                            // 如果是文本文件，尝试读取内容
                            if fileURL.pathExtension.lowercased() == "txt" {
                                do {
                                    let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                                    extractedText += fileContent
                                    extractionSuccess = true
                                } catch {
                                    print("读取文件内容出错: \(error.localizedDescription)")
                                    
                                    // 尝试其他编码
                                    do {
                                        // 使用正确的GB18030编码
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
        
        // 等待所有异步操作完成
        dispatchGroup.notify(queue: .main) {
            if !extractedText.isEmpty && extractionSuccess {
                // 成功提取文本，现在将其传递给主应用
                self.openMainAppWithText(extractedText)
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    private func openMainAppWithText(_ text: String) {
        // 编码文本，以便作为URL参数传递
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("无法对文本进行URL编码")
            return
        }
        
        // 创建URL Scheme来打开主应用并传递文本
        let urlString = "textreader://import?text=\(encodedText)"
        
        if let url = URL(string: urlString) {
            // 在扩展中，使用extensionContext的openURL方法
            self.extensionContext?.open(url, completionHandler: { success in
                if success {
                    print("成功打开URL: \(urlString)")
                } else {
                    print("无法打开URL: \(urlString)")
                    // 如果无法打开，关闭分享扩展
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
