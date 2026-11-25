import SwiftUI
import AVFoundation

/// 朗读语音的归类与叫法。系统给的只有名字（Tingting、Meijia…），看不出是普通话还是粤语。
enum VoiceCatalog {
    struct Group: Identifiable {
        let language: String
        let title: String
        let voices: [AVSpeechSynthesisVoice]

        var id: String { language }
    }

    /// 常用的排在前面，其余按语言代码排序。
    private static let preferredLanguageOrder = ["zh-CN", "zh-TW", "zh-HK"]

    static func regionTitle(forLanguage language: String) -> String {
        switch language {
        case "zh-CN":
            return "普通话（中国大陆）"
        case "zh-TW":
            return "国语（台湾）"
        case "zh-HK":
            return "粤语（香港）"
        default:
            return Locale(identifier: "zh-Hans").localizedString(forIdentifier: language) ?? language
        }
    }

    static func shortRegionTitle(forLanguage language: String) -> String {
        switch language {
        case "zh-CN":
            return "普通话"
        case "zh-TW":
            return "国语"
        case "zh-HK":
            return "粤语"
        default:
            return regionTitle(forLanguage: language)
        }
    }

    static func qualityTitle(for quality: AVSpeechSynthesisVoiceQuality) -> String? {
        switch quality {
        case .enhanced:
            return "增强音质"
        case .premium:
            return "高级音质"
        default:
            return nil
        }
    }

    static func sortedLanguages(_ languages: [String]) -> [String] {
        Array(Set(languages)).sorted { lhs, rhs in
            let lhsRank = preferredLanguageOrder.firstIndex(of: lhs) ?? preferredLanguageOrder.count
            let rhsRank = preferredLanguageOrder.firstIndex(of: rhs) ?? preferredLanguageOrder.count
            return lhsRank == rhsRank ? lhs < rhs : lhsRank < rhsRank
        }
    }

    static func groups(for voices: [AVSpeechSynthesisVoice]) -> [Group] {
        sortedLanguages(voices.map(\.language)).map { language in
            Group(
                language: language,
                title: regionTitle(forLanguage: language),
                voices: voices.filter { $0.language == language }
            )
        }
    }

    /// 设置首页「语音」那一行右边显示的说法，例如「Tingting · 普通话」。
    static func summary(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) · \(shortRegionTitle(forLanguage: voice.language))"
    }
}

/// 选朗读语音：按地区分组，点一下就选中并念一句样例。
struct VoicePickerView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        List {
            ForEach(VoiceCatalog.groups(for: viewModel.availableVoices)) { group in
                Section(group.title) {
                    ForEach(group.voices, id: \.identifier) { voice in
                        voiceRow(voice)
                    }
                }
            }

            Section {
            } footer: {
                Text(viewModel.isReading
                     ? "正在朗读时，点一个语音会立刻换成它接着读。"
                     : "点一个语音会念一句样例，听听是不是想要的声音。")
            }
        }
        .navigationTitle("语音")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.availableVoices.isEmpty {
                ContentUnavailableView {
                    Label("没有可用的中文语音", systemImage: "waveform.slash")
                } description: {
                    Text("可以在系统「设置 › 辅助功能 › 朗读内容 › 声音」里下载中文语音。")
                }
            }
        }
        .onDisappear {
            viewModel.stopVoicePreview()
        }
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected = voice.identifier == viewModel.selectedVoiceIdentifier
        return Button {
            viewModel.selectVoice(identifier: voice.identifier)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .foregroundStyle(Color.primary)

                    if let quality = VoiceCatalog.qualityTitle(for: voice.quality) {
                        Text(quality)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(viewModel.currentAccentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
