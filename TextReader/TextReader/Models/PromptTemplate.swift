import Foundation

struct PromptTemplate: Identifiable, Codable, Hashable {
    /// 套好模板之后把提示词送到哪里。
    enum Destination: String, Codable, CaseIterable, Identifiable {
        case copyOnly
        case perplexity
        case raycast

        var id: String { rawValue }

        /// 设置项里的完整说法。
        var displayName: String {
            switch self {
            case .copyOnly:
                return "仅复制"
            case .perplexity:
                return "复制并打开 Perplexity"
            case .raycast:
                return "复制并打开 Raycast"
            }
        }

        /// 列表副标题里的简短说法。
        var shortName: String {
            switch self {
            case .copyOnly:
                return "仅复制"
            case .perplexity:
                return "打开 Perplexity"
            case .raycast:
                return "打开 Raycast"
            }
        }
    }

    let id: UUID
    var name: String
    var content: String
    /// 旧版本保存的模板没有这一项（nil）：第一次使用时再问，选过之后记住。
    var destination: Destination?
    
    init(id: UUID = .init(), name: String, content: String, destination: Destination? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.destination = destination
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, content, destination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        content = try container.decode(String.self, forKey: .content)
        // 认不出的取值当作「还没选过」，不能让整份模板列表因此解码失败而清空。
        let rawDestination = (try? container.decodeIfPresent(String.self, forKey: .destination)) ?? nil
        destination = rawDestination.flatMap(Destination.init(rawValue:))
    }
}
