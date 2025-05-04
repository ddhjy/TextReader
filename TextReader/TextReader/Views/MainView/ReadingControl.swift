import SwiftUI

struct ReadingControl: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("音色")
                Spacer()
                Picker("音色", selection: $viewModel.selectedVoiceIdentifier) {
                    ForEach(viewModel.availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier as String?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            HStack {
                Text("速度")
                Spacer()
                Picker("速度", selection: $viewModel.readingSpeed) {
                    Text("1x").tag(1.0 as Float)
                    Text("1.5x").tag(1.5 as Float)
                    Text("1.75").tag(1.75 as Float)
                    Text("2x").tag(2.0 as Float)
                    Text("3x").tag(3.0 as Float)
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
        .padding(.horizontal)
    }
} 