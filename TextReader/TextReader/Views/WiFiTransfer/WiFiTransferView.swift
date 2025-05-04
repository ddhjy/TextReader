import SwiftUI

struct WiFiTransferView: View {
    // 观察 ContentViewModel 以获取 WiFi 服务状态和控制方法
    @ObservedObject var viewModel: ContentViewModel
    // 用于关闭 Sheet
    @Environment(\.dismiss) private var dismiss
    // 本地状态，用于显示"已复制"提示
    @State private var isCopied = false

    var body: some View {
        NavigationView { // Wrap in NavigationView to show title and toolbar
            VStack(spacing: 20) {
                Spacer() // 顶部留白

                // 根据 WiFi 服务是否正在运行显示不同内容
                if viewModel.isServerRunning {
                    // --- 服务运行中 UI ---
                    Image(systemName: "wifi")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                    Text("WiFi 传输已开启")
                        .font(.title2)
                        .padding(.bottom, 10)

                    // 显示服务器地址和复制按钮
                    if let address = viewModel.serverAddress {
                        Text("请在同一 WiFi 网络下的浏览器中访问以下地址进行文件上传：")
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

                            Spacer() // 将按钮推到右侧

                            // 复制按钮
                            Button {
                                UIPasteboard.general.string = address
                                print("地址已复制: \(address)")
                                isCopied = true
                                // 1.5 秒后自动隐藏"已复制"提示
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isCopied = false
                                }
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(isCopied ? .green : .accentColor) // 复制成功显示绿色对勾
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain) // 使用简洁按钮样式
                            .padding(.trailing)
                        }
                        .padding(.vertical, 8)
                        .background(Color(UIColor.secondarySystemBackground)) // 背景增加对比度
                        .cornerRadius(8)
                        .padding(.horizontal) // 限制背景宽度

                    } else {
                        // 地址尚未获取时显示提示
                        Text("正在获取 IP 地址...")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    }

                    // 关闭服务按钮
                    Button("关闭 WiFi 传输") {
                        viewModel.toggleWiFiTransfer() // 调用 ViewModel 的方法停止服务
                    }
                    .buttonStyle(.borderedProminent) // 突出按钮样式
                    .tint(.red) // 红色表示关闭操作
                    .padding(.top)

                } else {
                    // --- 服务未运行 UI ---
                     Image(systemName: "wifi.slash")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray) // 灰色表示未激活
                    Text("WiFi 传输已关闭")
                        .font(.title2)
                        .padding(.bottom, 10)
                    Text("点击下方按钮启动服务，即可通过 WiFi 向 App 传输 TXT 文件。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // 启动服务按钮
                    Button("启动 WiFi 传输") {
                        viewModel.toggleWiFiTransfer() // 调用 ViewModel 的方法启动服务
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue) // 蓝色表示启动操作
                    .padding(.top)
                }

                Spacer() // 底部留白
                Spacer() // 增加底部留白比重
            }
            .padding() // 给 VStack 整体添加内边距
            .navigationTitle("WiFi 传书") // 页面标题
            .navigationBarTitleDisplayMode(.inline) // 小标题样式
            .toolbar {
                // 添加右上角完成按钮，用于关闭 Sheet
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss() // 关闭当前视图
                    }
                }
            }
            // 注意：这里没有添加 onAppear/onDisappear 逻辑来自动开关服务，
            // 当前设计为用户手动在此页面控制服务的启停。
            // 如果需要自动开关，可以取消下面的注释。
            /*
             .onAppear {
                 if !viewModel.isServerRunning {
                     viewModel.toggleWiFiTransfer() // 页面出现时自动启动
                 }
             }
            */
             .onDisappear {
                 if viewModel.isServerRunning {
                     viewModel.toggleWiFiTransfer() // 页面消失时如果服务在运行，则自动停止
                 }
             }
        } // End NavigationView
    }
}

// 预览代码 (可选，方便 SwiftUI 预览)
// struct WiFiTransferView_Previews: PreviewProvider {
//     static var previews: some View {
//         // 创建一个模拟的 ViewModel 实例用于预览
//         let mockViewModel = ContentViewModel()
//         // 可以设置不同的模拟状态来预览不同场景
//         // mockViewModel.isServerRunning = true
//         // mockViewModel.serverAddress = "http://192.168.1.10:8080"
//
//         // 需要包裹在 NavigationView 中以显示标题和工具栏
// //        NavigationView { // Preview already wrapped in NavigationView
//              WiFiTransferView(viewModel: mockViewModel)
// //         }
//     }
// } 