import SwiftUI

struct WiFiTransferView: View {
    // Observe ContentViewModel for WiFi service status and control methods
    @ObservedObject var viewModel: ContentViewModel
    // Used to dismiss the Sheet
    @Environment(\.dismiss) private var dismiss
    // Local state to show "Copied" feedback
    @State private var isCopied = false

    var body: some View {
        NavigationView { // Wrap in NavigationView to show title and toolbar
            VStack(spacing: 20) {
                Spacer() // Top padding

                // Display different content based on whether WiFi service is running
                if viewModel.isServerRunning {
                    // --- Service Running UI ---
                    Image(systemName: "wifi")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                    Text("WiFi Transfer Active")
                        .font(.title2)
                        .padding(.bottom, 10)

                    // Display server address and copy button
                    if let address = viewModel.serverAddress {
                        Text("Visit the following address in a browser on the same WiFi network to upload files:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        HStack {
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading)

                            Spacer() // Pushes the button to the right

                            // Copy button
                            Button {
                                UIPasteboard.general.string = address
                                print("Address copied: \(address)")
                                isCopied = true
                                // Automatically hide "Copied" feedback after 1.5 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isCopied = false
                                }
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(isCopied ? .green : .accentColor) // Show green checkmark on success
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain) // Use plain button style
                            .padding(.trailing)
                        }
                        .padding(.vertical, 8)
                        .background(Color(UIColor.secondarySystemBackground)) // Background adds contrast
                        .cornerRadius(8)
                        .padding(.horizontal) // Limit background width

                    } else {
                        // Show a message while fetching the address
                        Text("Fetching IP Address...")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    }

                    // Stop service button
                    Button("Stop WiFi Transfer") {
                        viewModel.toggleWiFiTransfer() // Call ViewModel method to stop service
                    }
                    .buttonStyle(.borderedProminent) // Prominent button style
                    .tint(.red) // Red indicates a stop action
                    .padding(.top)

                } else {
                    // --- Service Not Running UI ---
                     Image(systemName: "wifi.slash")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray) // Gray indicates inactive
                    Text("WiFi Transfer Inactive")
                        .font(.title2)
                        .padding(.bottom, 10)
                    Text("Tap the button below to start the service and transfer TXT files to the app via WiFi.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Start service button
                    Button("Start WiFi Transfer") {
                        viewModel.toggleWiFiTransfer() // Call ViewModel method to start service
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue) // Blue indicates a start action
                    .padding(.top)
                }

                Spacer() // Bottom padding
                Spacer() // Increase bottom padding weight
            }
            .padding() // Add padding to the whole VStack
            .navigationTitle("WiFi Transfer") // Page title
            .navigationBarTitleDisplayMode(.inline) // Inline title style
            .toolbar {
                // Add Done button in the top right to close the Sheet
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss() // Close the current view
                    }
                }
            }
            // Note: No onAppear/onDisappear logic added here to automatically toggle the service.
            // Current design requires manual start/stop on this page.
            // Uncomment below if automatic toggling is needed.
            /*
             .onAppear {
                 if !viewModel.isServerRunning {
                     viewModel.toggleWiFiTransfer() // Automatically start on appear
                 }
             }
            */
             .onDisappear {
                 if viewModel.isServerRunning {
                     viewModel.toggleWiFiTransfer() // Automatically stop if running when view disappears
                 }
             }
        } // End NavigationView
    }
}

// Preview code (Optional, for SwiftUI Previews)
// struct WiFiTransferView_Previews: PreviewProvider {
//     static var previews: some View {
//         // Create a mock ViewModel instance for previewing
//         let mockViewModel = ContentViewModel()
//         // Can set different mock states to preview different scenarios
//         // mockViewModel.isServerRunning = true
//         // mockViewModel.serverAddress = "http://192.168.1.10:8080"
//
//         // Needs to be wrapped in NavigationView to show title and toolbar
//         // NavigationView { // Preview already wrapped in NavigationView
//              WiFiTransferView(viewModel: mockViewModel)
//         // }
//     }
// } 