import SwiftUI

struct WiFiTransferView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                if viewModel.isServerRunning {
                    Image(systemName: "wifi")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(viewModel.currentAccentColor)
                    Text("WiFi Transfer Active")
                        .font(.title2)
                        .padding(.bottom, 10)

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

                            Spacer()

                            Button {
                                UIPasteboard.general.string = address
                                print("Address copied: \(address)")
                                isCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isCopied = false
                                }
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(isCopied ? .green : .accentColor)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing)
                        }
                        .padding(.vertical, 8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                        .padding(.horizontal)

                    } else {
                        Text("Fetching IP Address...")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    }

                    Button("Stop WiFi Transfer") {
                        viewModel.toggleWiFiTransfer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.top)

                } else {
                     Image(systemName: "wifi.slash")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray)
                    Text("WiFi Transfer Inactive")
                        .font(.title2)
                        .padding(.bottom, 10)
                    Text("Tap the button below to start the service and transfer TXT files to the app via WiFi.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Start WiFi Transfer") {
                        viewModel.toggleWiFiTransfer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.currentAccentColor)
                    .padding(.top)
                }

                Spacer()
                Spacer()
            }
            .padding()
            .navigationTitle("WiFi Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(viewModel.currentAccentColor)
                }
            }
            .onDisappear {
                if viewModel.isServerRunning {
                    viewModel.toggleWiFiTransfer()
                }
            }
        }
    }
} 