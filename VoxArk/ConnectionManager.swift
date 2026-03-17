import Foundation
import MultipeerConnectivity
import Combine

class ConnectionManager: NSObject, ObservableObject {
    // 通信のグループ名（※15文字以内、小文字、ハイフンのみという厳格なルールがあります）
    private static let serviceType = "voxark-chat"
    
    // 画面側に「今繋がっている人」を教えるための配列
    @Published var connectedPeers: [MCPeerID] = []
    
    private var peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    
    override init() {
        // 設定画面で保存した「第2ネーム（例：フクロウ7681）」を引っ張ってくる
        let savedName = UserDefaults.standard.string(forKey: "secondName") ?? "ゲスト"
        let displayName = savedName.isEmpty ? "ゲスト" : savedName
        
        // 自分の名札を作成
        self.peerID = MCPeerID(displayName: displayName)
        
        // 通信セッション（パイプ）を作成
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        
        // 自分の看板を出す人（Advertiser）と、周囲を探す人（Browser）を準備
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        
        super.init()
        
        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self
    }
    
    // 🔌 通信の待機と探索をスタートする
    func startNetworking() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        print("🌐 通信の待機と探索を開始しました")
    }
    
    // 🔌 通信をストップする
    func stopNetworking() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
    }
}

// MARK: - MCSessionDelegate (通信状態の監視)
extension ConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            switch state {
            case .connected:
                print("✅ 接続成功: \(peerID.displayName)")
            case .connecting:
                print("⏳ 接続中: \(peerID.displayName)")
            case .notConnected:
                print("❌ 切断: \(peerID.displayName)")
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // ★次回、ここに「相手からテキストやメタデータを受け取った時の処理」を書きます
    }
    
    // 以下は今回は使わない必須メソッドたち
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (招待された時の処理)
extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // テスト用：見つかったら無条件で自動接続する
        print("📩 招待を受け入れました: \(peerID.displayName)")
        invitationHandler(true, self.session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (相手を見つけた時の処理)
extension ConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("👀 ユーザー発見: \(peerID.displayName) -> 自動で招待を送ります")
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("💨 ユーザーを見失いました: \(peerID.displayName)")
    }
}
