import Foundation
import MultipeerConnectivity
import Combine

// ★ 新規追加：通信で送り合う「メタデータ付きの小包」の設計図
struct ChatPayload: Codable, Identifiable {
    var id = UUID() // ★ これを追加
    let text: String
    let senderName: String
    let senderGender: String
    let senderLanguage: String
}


@MainActor
class ConnectionManager: NSObject, ObservableObject {
    private let serviceType = "voxark-chat"
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    @Published var connectedPeers: [MCPeerID] = []
    
    // ★ 新規追加：受信した小包をChatViewに渡すための変数
    @Published var receivedPayload: ChatPayload?
    
    override init() {
        super.init()
        let savedName = UserDefaults.standard.string(forKey: "secondName") ?? "Unknown"
        self.peerID = MCPeerID(displayName: savedName)
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.session.delegate = self
        
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        self.advertiser.delegate = self
        
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        self.browser.delegate = self
    }
    
    func startNetworking() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }
    
    func stopNetworking() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
    }
    
    // ★ 新規追加：メタデータ付きで送信する関数
    func sendMessage(text: String, myName: String, myGender: String, myLanguage: String) {
        guard !session.connectedPeers.isEmpty else { return }
        
        let payload = ChatPayload(text: text, senderName: myName, senderGender: myGender, senderLanguage: myLanguage)
        
        do {
            let data = try JSONEncoder().encode(payload)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("送信エラー: \(error)")
        }
    }
}

extension ConnectionManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeers = session.connectedPeers
        }
    }
    
    // ★ 新規追加：データを受け取った時の処理
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                // 受け取ったデータを小包（ChatPayload）に解読する
                let payload = try JSONDecoder().decode(ChatPayload.self, from: data)
                self.receivedPayload = payload
            } catch {
                print("受信データの解読エラー: \(error)")
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// ★ 修正後の extension（ConnectionManager.swift の一番下）

extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // ★ 表舞台（MainActor）の session を安全に使うための Task
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}

extension ConnectionManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // ★ 表舞台（MainActor）の session を安全に使うための Task
        Task { @MainActor in
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
