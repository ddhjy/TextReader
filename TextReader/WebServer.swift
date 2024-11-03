import Network

class WebServer: NSObject {
    private var listener: NWListener?
    private var isRunning = false
    var onFileReceived: ((String, String) -> Void)?
    
    func start() -> String? {
        let parameters = NWParameters.tcp
        listener = try? NWListener(using: parameters, on: 8080)
        
        listener?.newConnectionHandler = { [weak self] connection in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("客户端已连接")
                case .failed(let error):
                    print("连接失败: \(error)")
                case .cancelled:
                    print("连接已取消")
                default:
                    break
                }
            }
            
            connection.start(queue: .main)
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed(let error):
                print("启动服务器失败: \(error)")
                self?.isRunning = false
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
        return getLocalIPAddress()
    }
    
    func stop() {
        listener?.cancel()
        isRunning = false
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface?.ifa_addr,
                              socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                              &hostname,
                              socklen_t(hostname.count),
                              nil,
                              0,
                              NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
} 