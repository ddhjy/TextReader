import Foundation

final class TemplateManager {
    private let fileName = "templates.json"
    private let fm: FileManager
    private let documentsDirectoryProvider: () -> URL

    init(fileManager: FileManager = .default,
         documentsDirectoryProvider: (() -> URL)? = nil) {
        self.fm = fileManager
        self.documentsDirectoryProvider = documentsDirectoryProvider ?? {
            guard let doc = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("无法访问文档目录")
            }
            return doc
        }
    }
    
    private func templateURL() -> URL {
        documentsDirectoryProvider().appendingPathComponent(fileName)
    }
    
    func load() -> [PromptTemplate] {
        guard let data = try? Data(contentsOf: templateURL()) else {
            let defaults = [
              PromptTemplate(name: "总结式", content: "请用中文总结以下内容：{selection}"),
              PromptTemplate(name: "翻译-EN", content: "Translate into English:\n{selection}")
            ]
            _ = save(defaults)
            return defaults
        }
        return (try? JSONDecoder().decode([PromptTemplate].self, from: data)) ?? []
    }
    
    @discardableResult
    func save(_ list:[PromptTemplate]) -> Bool {
        guard let data = try? JSONEncoder().encode(list) else { return false }
        do { try data.write(to: templateURL(), options: .atomic) ; return true }
        catch { print("⚠️ save templates failed:", error); return false }
    }
} 
