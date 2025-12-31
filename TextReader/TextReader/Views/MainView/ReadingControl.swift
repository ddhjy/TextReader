import SwiftUI
import UIKit

struct ReadingControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    private let speedOptions: [Float] = [1.0, 1.75, 3.0]
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    private func speedLabel(_ v: Float) -> String { v == floor(v) ? "\(Int(v))x" : String(format:"%.2gx", v) }
    
    private func voiceNameById(_ id: String?) -> String {
        viewModel.availableVoices.first(where: { $0.identifier == id })?.name ?? "默认"
    }
    
    private func labelForPicker(value: String) -> some View {
        Text(value)
            .frame(minWidth: 60, alignment: .trailing)
    }

    var body: some View {
        VStack(spacing: 8) {
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