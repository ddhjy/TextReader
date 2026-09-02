import SwiftUI

struct WiFiTransferView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isServerRunning {
                    List {
                        Section {
                            HStack {
                                Label("传输服务", systemImage: "wifi")
                                    .foregroundStyle(viewModel.currentAccentColor)
                                Spacer()
                                Text("运行中")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            if let address = viewModel.serverAddress {
                                HStack {
                                    Text(address)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
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
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("拷贝地址")
                                    .sensoryFeedback(.success, trigger: isCopied) { _, new in new }
                                }
                            } else {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("正在准备服务地址…")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("在电脑浏览器中打开")
                        } footer: {
                            Text("确保手机与电脑连接到同一 Wi‑Fi 网络。")
                        }

                        if let p = viewModel.wifiUploadProgress {
                            Section("正在接收") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(viewModel.wifiUploadFilename ?? "文件")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    ProgressView(value: p)
                                    HStack {
                                        Spacer()
                                        Text("\(Int(p * 100))%")
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if let err = viewModel.wifiUploadError {
                            Section {
                                Label(err, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                viewModel.toggleWiFiTransfer()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("停止传输")
                                    Spacer()
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Wi‑Fi 传书", systemImage: "wifi")
                    } description: {
                        Text("在同一局域网下的电脑浏览器中打开指定地址，即可直接传入 TXT 文件。")
                    } actions: {
                        Button("开始传输") {
                            viewModel.toggleWiFiTransfer()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.currentAccentColor)
                    }
                }
            }
            .navigationTitle("Wi‑Fi 传输")
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
