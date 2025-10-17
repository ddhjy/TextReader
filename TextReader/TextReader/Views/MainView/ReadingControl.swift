import SwiftUI
import UIKit

/// 阅读控制组件，用于控制朗读语音和速度设置
struct ReadingControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    // MARK: - 私有属性
    
    private let speedOptions: [Float] = [1.0, 1.75, 3.0]
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    /// 将速度值格式化为显示文本
    /// - Parameter v: 速度值
    /// - Returns: 格式化后的速度字符串（例如：1x、1.5x）
    private func speedLabel(_ v: Float) -> String { v == floor(v) ? "\(Int(v))x" : String(format:"%.2gx", v) }
    
    /// 根据语音ID获取语音名称
    /// - Parameter id: 语音ID
    /// - Returns: 语音名称，如果未找到则返回"默认"
    private func voiceNameById(_ id: String?) -> String {
        viewModel.availableVoices.first(where: { $0.identifier == id })?.name ?? "默认"
    }
    
    /// 创建选择器的标签视图
    /// - Parameter value: 标签文本
    /// - Returns: 格式化的标签视图
    private func labelForPicker(value: String) -> some View {
        Text(value)
            .frame(minWidth: 60, alignment: .trailing)
    }

    var body: some View {
        VStack(spacing: 8) {
            // MARK: - 语音选择
            HStack {
                Text("语音")
                Spacer()
                Menu {
                    ForEach(viewModel.availableVoices, id: \.identifier) { voice in
                        Button(action: { viewModel.selectedVoiceIdentifier = voice.identifier }) {
                            Text(voice.name)
                        }
                    }
                } label: {
                    labelForPicker(value: voiceNameById(viewModel.selectedVoiceIdentifier))
                }
            }

            // MARK: - 速度选择
            HStack {
                Text("速度")
                Spacer()
                HStack(spacing: 8) {
                    ForEach(speedOptions, id:\.self) { speed in
                        Button(action:{
                            viewModel.readingSpeed = speed
                            feedbackGenerator.impactOccurred()
                        }) {
                            Text(speedLabel(speed))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(viewModel.readingSpeed == speed ? Color.accentColor : Color.clear)
                                )
                                .foregroundColor(viewModel.readingSpeed == speed ? .white : .primary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
}