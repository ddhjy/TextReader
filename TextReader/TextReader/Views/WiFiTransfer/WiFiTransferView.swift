import SwiftUI
import UIKit

struct WiFiTransferView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isServerRunning {
                    runningContent
                } else {
                    ContentUnavailableView {
                        Label("Wi‑Fi 传书", systemImage: "wifi")
                    } description: {
                        Text("在电脑浏览器中打开地址，即可传入 TXT 文件")
                    } actions: {
                        Button("开始传输") {
                            viewModel.toggleWiFiTransfer()
                        }
                        .buttonStyle(.borderedProminent)
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

    private var runningContent: some View {
        List {
            Section {
                LabeledContent {
                    Text("传输已就绪")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("状态", systemImage: "wifi")
                }
            }

            Section {
                if let address = viewModel.serverAddress {
                    HStack(spacing: 12) {
                        Text(address)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Button {
                            UIPasteboard.general.string = address
                            isCopied = true
                        } label: {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isCopied ? "已复制" : "复制地址")
                        .sensoryFeedback(.success, trigger: isCopied)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("正在准备…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("在电脑浏览器中打开")
            } footer: {
                Text("确保电脑与手机在同一 Wi‑Fi")
            }

            if let progress = viewModel.wifiUploadProgress {
                Section("正在接收") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.wifiUploadFilename ?? "文件")
                            .font(.subheadline)
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = viewModel.wifiUploadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("停止传输", role: .destructive) {
                    viewModel.toggleWiFiTransfer()
                }
            }
        }
    }
}
