import SwiftUI
import UIKit

struct WiFiTransferView: View {
    @ObservedObject var viewModel: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    /// 最近一次点「复制地址」的时刻。两秒后清空，按钮回到「复制地址」。
    @State private var copiedAt: Date?

    private var records: [WiFiTransferService.TransferRecord] {
        viewModel.wifiTransferRecords
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection

                if let upload = viewModel.wifiUpload {
                    receivingSection(upload)
                }

                recordsSection
            }
            .navigationTitle("Wi‑Fi 传书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .tint(viewModel.currentAccentColor)
        // 进页面就开始接收，不用再找一个「开始」按钮；离开页面就停。
        .onAppear {
            viewModel.beginWiFiTransferSession()
            // 传书时人在电脑前操作，手机放在一边；锁屏后电脑就连不上了，所以停在这一页时不自动锁屏。
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.endWiFiTransferSession()
        }
    }

    // MARK: - 状态

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.wifiStatus {
        case .stopped, .starting:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在准备…")
                        .foregroundStyle(.secondary)
                }
            }

        case .ready(let address):
            readySection(address: address)

        case .noWiFi:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("手机没有连上 Wi‑Fi", systemImage: "wifi.slash")
                        .font(.headline)

                    Text("先让手机和电脑连上同一个 Wi‑Fi。连上之后，这里会自动显示要打开的地址。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Button {
                        viewModel.retryWiFiTransfer()
                    } label: {
                        Text("重试")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func readySection(address: String) -> some View {
        Section {
            VStack(spacing: 14) {
                // 地址要整段看得全：宁可缩小字号，也不从中间截断成「http://192…:8080」。
                Text(address)
                    .font(.title3.monospaced().weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("地址 \(address)")

                Button {
                    UIPasteboard.general.string = address
                    copiedAt = Date()
                } label: {
                    // 图标和字自己排成一行，放不下就缩小。交给系统的 Label 排，字号调到最大时
                    // 会折成两行、图标不见、「制」字被切掉一半。
                    HStack(spacing: 8) {
                        Image(systemName: copiedAt == nil ? "doc.on.doc" : "checkmark")
                            .accessibilityHidden(true)
                        Text(copiedAt == nil ? "复制地址" : "已复制")
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .sensoryFeedback(.success, trigger: copiedAt) { _, newValue in
                    newValue != nil
                }
                .task(id: copiedAt) {
                    guard copiedAt != nil else { return }
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    copiedAt = nil
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("在电脑浏览器里打开这个地址")
        } footer: {
            Text("电脑和手机要连同一个 Wi‑Fi。传书时请停在这一页，离开后就收不到了。支持 TXT 和 MD 文件。")
        }
    }

    // MARK: - 正在接收

    private func receivingSection(_ upload: ContentViewModel.WiFiUploadProgress) -> some View {
        Section("正在接收") {
            VStack(alignment: .leading, spacing: 8) {
                Text(upload.fileName ?? "文件")
                    .font(.subheadline)
                    .lineLimit(2)

                if let fraction = upload.fraction {
                    ProgressView(value: fraction)
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 结果

    /// 传完的结果一直留在这里：成功的、没成功的各是哪一本，不用回书架去猜。
    private var recordsSection: some View {
        Section {
            if records.isEmpty {
                Text("传进来的书会列在这里")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    recordRow(record)
                }
            }
        } header: {
            Text(Self.recordsSummary(for: records))
        }
    }

    private func recordRow(_ record: WiFiTransferService.TransferRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.succeeded ? Color.green : Color.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.fileName)
                    .font(.body)
                    .lineLimit(2)

                Text(record.detail)
                    .font(.subheadline)
                    .foregroundStyle(record.succeeded ? Color.secondary : Color.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.succeeded ? "已收到" : "没有收到")，\(record.fileName)，\(record.detail)")
    }

    static func recordsSummary(for records: [WiFiTransferService.TransferRecord]) -> String {
        let succeeded = records.filter(\.succeeded).count
        let failed = records.count - succeeded

        switch (succeeded, failed) {
        case (0, 0):
            return "本次传书"
        case (_, 0):
            return "已收到 \(succeeded) 本"
        case (0, _):
            return "\(failed) 个没传成功"
        default:
            return "已收到 \(succeeded) 本，\(failed) 个没传成功"
        }
    }
}
