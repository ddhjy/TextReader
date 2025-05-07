import Foundation

final class TemplateManager {
    private let fileName = "templates.json"
    private let fm = FileManager.default
    
    private func templateURL() throws -> URL {
        let doc = try fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return doc.appendingPathComponent(fileName)
    }
    
    func load() -> [PromptTemplate] {
        guard let data = try? Data(contentsOf: try! templateURL()) else {
            // 首次启动写入默认模板
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
        do { try data.write(to: try templateURL(), options: .atomic) ; return true }
        catch { print("⚠️ save templates failed:", error); return false }
    }
} 