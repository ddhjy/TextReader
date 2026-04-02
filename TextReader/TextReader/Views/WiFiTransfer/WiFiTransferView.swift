import SwiftUI

struct WiFiTransferView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if viewModel.isServerRunning {
                    Image(systemName: "wifi")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(viewModel.currentAccentColor)
                    Text("传输已就绪")
                        .font(.title2)
                        .padding(.bottom, 10)

                    if let p = viewModel.wifiUploadProgress {
                        VStack(spacing: 8) {
                            Text("正在接收：\(viewModel.wifiUploadFilename ?? "文件")")
                                .font(.subheadline)
                            ProgressView(value: p)
                            Text("\(Int(p * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                    }
                    if let err = viewModel.wifiUploadError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.horizontal)
                    }

                    if let address = viewModel.serverAddress {
                        Text("确保电脑与手机在同一 WiFi 下，在浏览器打开：")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                                isCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isCopied = false
                                }
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(isCopied ? .green : viewModel.currentAccentColor)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing)
                        }
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)

                    } else {
                        Text("正在准备…")
                            .foregroundStyle(.secondary)
                            .padding(.vertical)
                    }

                    Button("停止传输") {
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
                        .foregroundStyle(.gray)
                    Text("WiFi 传书")
                        .font(.title2)
                        .padding(.bottom, 10)
                    Text("在电脑浏览器中打开地址，即可传入 TXT 文件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("开始传输") {
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
            .navigationTitle("WiFi 传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                if viewModel.isServerRunning {
                    viewModel.toggleWiFiTransfer()
                }
            }
        }
        .tint(viewModel.currentAccentColor)
    }
}
