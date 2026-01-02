import SwiftUI
import UIKit

struct PageControl: View {
    @ObservedObject var viewModel: ContentViewModel
    
    private let haptic = UISelectionFeedbackGenerator()
    
    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(viewModel.currentPageIndex) },
            set: { newVal in
                let newIndex = Int(newVal.rounded())
                guard newIndex != viewModel.currentPageIndex else { return }
                
                guard !viewModel.pages.isEmpty,
                      newIndex >= 0,
                      newIndex < viewModel.pages.count else { return }
                
                haptic.selectionChanged()
                haptic.prepare()
                
                viewModel.goToPage(newIndex)
            }
        )
    }
    
    var body: some View {
        Group {
            if viewModel.pages.count > 1 {
                CustomSlider(
                    value: sliderBinding,
                    range: 0...Double(max(0, viewModel.pages.count - 1)),
                    accentColor: viewModel.currentAccentColor
                )
                .frame(height: 18)
            } else {
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                    .tint(viewModel.currentAccentColor)
                    .disabled(true)
                    .frame(height: 18)
            }
        }
        .padding(.horizontal, 8)
        .onAppear {
            haptic.prepare()
        }
    }
}

private struct CustomSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.tintColor = UIColor(accentColor)
        slider.thumbTintColor = UIColor.clear
        slider.minimumTrackTintColor = UIColor(accentColor)
        slider.maximumTrackTintColor = UIColor.systemGray4
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        
        return slider
    }
    
    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.minimumValue = Float(range.lowerBound)
        uiView.maximumValue = Float(range.upperBound)
        
        let clampedValue = min(max(Float(value), uiView.minimumValue), uiView.maximumValue)
        if abs(uiView.value - clampedValue) > 0.01 {
            uiView.value = clampedValue
        }
        
        uiView.tintColor = UIColor(accentColor)
        uiView.minimumTrackTintColor = UIColor(accentColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: CustomSlider
        
        init(_ parent: CustomSlider) {
            self.parent = parent
        }
        
        @objc func valueChanged(_ sender: UISlider) {
            let clampedValue = Double(min(max(sender.value, sender.minimumValue), sender.maximumValue))
            parent.value = clampedValue
        }
    }
} 
