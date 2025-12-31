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
                    Text("WiFi 传输已开启")
                        .font(.title2)
                        .padding(.bottom, 10)

                    if let p = viewModel.wifiUploadProgress {
                        VStack(spacing: 8) {
                            Text("正在接收：\(viewModel.wifiUploadFilename ?? "未知")")
                                .font(.subheadline)
                            ProgressView(value: p)
                            Text("\(Int(p * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    if let err = viewModel.wifiUploadError {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .padding(.horizontal)
                    }

                    if let address = viewModel.serverAddress {
                        Text("请在同一 WiFi 网络下，在浏览器访问以下地址上传文件：")
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
                        Text("正在获取 IP 地址…")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    }

                    Button("停止 WiFi 传输") {
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
                    Text("WiFi 传输未开启")
                        .font(.title2)
                        .padding(.bottom, 10)
                    Text("点击下方按钮以启动服务，通过 WiFi 传输 TXT 文件到应用。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("启动 WiFi 传输") {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
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