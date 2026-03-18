import SwiftUI
import AVFoundation

struct WPPost: Codable {
    let id: Int
    let title: RenderedText
    let content: RenderedText
    struct RenderedText: Codable { let rendered: String }
}

struct MyMemoryResponse: Codable {
    let responseData: ResponseData
    struct ResponseData: Codable { let translatedText: String }
}

// 🌐 画面の文字（UI）を翻訳する辞書（タイ語を追加！）
func localizedUI(_ key: String) -> String {
    // 🌟 ユーザーの「絶対に一番上にある言語」を強制取得する
    let rawLang = Locale.preferredLanguages.first ?? "ja"
    let baseLang = String(rawLang.prefix(2))
    
    let dictionary: [String: [String: String]] = [
        "app_title": [
            "ja": "VoxArk QRスキャナー", "en": "VoxArk QR Scanner",
            "zh": "VoxArk QR 扫描仪", "th": "VoxArk สแกนเนอร์ QR"
        ],
        "waiting": [
            "ja": "スキャン待機中...", "en": "Waiting for scan...",
            "zh": "等待扫描...", "th": "กำลังรอการสแกน..."
        ],
        "stop_btn": [
            "ja": "音声を強制ストップ", "en": "Stop Audio",
            "zh": "停止播放", "th": "หยุดเสียง"
        ],
        "scan_btn": [
            "ja": "QRコードをスキャン", "en": "Scan QR Code",
            "zh": "扫描二维码", "th": "สแกนคิวอาร์โค้ด"
        ],
        "stopped": [
            "ja": "停止しました。", "en": "Stopped.",
            "zh": "已停止。", "th": "หยุดแล้ว."
        ],
        "fetching": [
            "ja": "データを取得中...", "en": "Fetching data...",
            "zh": "获取数据中...", "th": "กำลังดึงข้อมูล..."
        ],
        "err_url": [
            "ja": "URLが無効です。", "en": "Invalid URL.",
            "zh": "无效的URL。", "th": "URL ไม่ถูกต้อง"
        ],
        "err_notfound": [
            "ja": "記事が見つかりません。", "en": "Article not found.",
            "zh": "找不到文章。", "th": "ไม่พบบทความ"
        ]
    ]
    
    // 見つからなければ英語を優先して返す（グローバル対応）
    return dictionary[key]?[baseLang] ?? dictionary[key]?["en"] ?? key
}

struct ContentView: View {
    @State private var fetchedText = localizedUI("waiting")
    @State private var isShowingScanner = false
    @State private var isError = false
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        VStack(spacing: 20) {
            Text(localizedUI("app_title")).font(.largeTitle).bold().padding(.top, 40)
            
            ScrollView {
                Text(fetchedText).font(.body).foregroundColor(isError ? .red : .primary).padding()
            }
            .frame(height: 350).frame(maxWidth: .infinity)
            .background(Color(.systemGray6)).cornerRadius(12).padding(.horizontal)
            
            Button(action: { SpeechSynthesizer.shared.stop(); self.fetchedText = localizedUI("stopped") }) {
                Label(localizedUI("stop_btn"), systemImage: "stop.circle.fill")
                    .font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity)
                    .background(Color.red).cornerRadius(12)
            }.padding(.horizontal)
            
            Button(action: { SpeechSynthesizer.shared.stop(); self.isShowingScanner = true }) {
                Label(localizedUI("scan_btn"), systemImage: "qrcode.viewfinder")
                    .font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity)
                    .background(Color.blue).cornerRadius(12)
            }.padding(.horizontal).padding(.bottom, 30)
        }
        .onChange(of: scenePhase) { newPhase in if newPhase != .active { SpeechSynthesizer.shared.stop() } }
        .sheet(isPresented: $isShowingScanner) {
            QRScannerView(fetchedText: self.$fetchedText, isShowingScanner: self.$isShowingScanner, onScan: self.fetchWordPressData)
        }
    }
    
    func fetchWordPressData(from urlString: String) {
        self.isError = false; self.fetchedText = localizedUI("fetching")
        
        guard let urlComponents = URLComponents(string: urlString), let host = urlComponents.host else {
            showError(localizedUI("err_url")); return
        }
        let baseDomain = "https://\(host)"
        var apiUrlString = "\(baseDomain)/wp-json/wp/v2/posts"
        if let id = extractPostId(from: urlString) { apiUrlString += "/\(id)" }
        else if let slug = urlString.split(separator: "/").last { apiUrlString += "?slug=\(slug)" }
        
        guard let url = URL(string: apiUrlString) else { showError(localizedUI("err_url")); return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            let post: WPPost?
            if let list = try? JSONDecoder().decode([WPPost].self, from: data) { post = list.first }
            else { post = try? JSONDecoder().decode(WPPost.self, from: data) }
            
            guard let finalPost = post else { showError(localizedUI("err_notfound")); return }
            let rawText = stripHTML(from: finalPost.title.rendered + "\n" + finalPost.content.rendered)
            self.processText(rawText)
        }.resume()
    }

    func processText(_ text: String) {
        // 🌟 翻訳する時も、ユーザーの絶対的な第1言語を取得する
        let rawLang = Locale.preferredLanguages.first ?? "ja"
        let baseLang = String(rawLang.prefix(2))
        
        if baseLang == "ja" {
            updateUI(text, lang: "ja-JP")
        } else {
            translate(text, to: baseLang)
        }
    }
    
    func translate(_ text: String, to lang: String) {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "ja|\(lang)")
        ]
        guard let url = components.url else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let res = try? JSONDecoder().decode(MyMemoryResponse.self, from: data) {
                let finalTranslatedText = stripHTML(from: res.responseData.translatedText)
                updateUI(finalTranslatedText, lang: lang)
            } else {
                showError("Translation Error")
            }
        }.resume()
    }
    
    func updateUI(_ text: String, lang: String) {
        DispatchQueue.main.async {
            self.fetchedText = text
            SpeechSynthesizer.shared.speak(text, language: lang)
        }
    }

    func showError(_ msg: String) { DispatchQueue.main.async { self.isError = true; self.fetchedText = msg } }
    
    func extractPostId(from url: String) -> String? {
        let patterns = [#"/(\d+)/?$"#, #"\?p=(\d+)"#]
        for p in patterns {
            if let range = url.range(of: p, options: .regularExpression) {
                let m = String(url[range])
                if let idR = m.range(of: #"\d+"#, options: .regularExpression) { return String(m[idR]) }
            }
        }
        return nil
    }
    
    func stripHTML(from str: String) -> String {
        guard let data = str.data(using: .utf8) else { return str }
        return (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil).string) ?? str
    }
}

class SpeechSynthesizer: NSObject {
    static let shared = SpeechSynthesizer()
    private let synth = AVSpeechSynthesizer()
    func speak(_ t: String, language: String) {
        stop()
        let utt = AVSpeechUtterance(string: t)
        
        // タイ語の音声コード（th-TH）をサポート
        var code = "en-US"
        if language == "ja" { code = "ja-JP" }
        else if language == "th" { code = "th-TH" }
        else if language == "zh" { code = "zh-CN" }
        
        utt.voice = AVSpeechSynthesisVoice(language: code)
        synth.speak(utt)
    }
    func stop() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } }
}

