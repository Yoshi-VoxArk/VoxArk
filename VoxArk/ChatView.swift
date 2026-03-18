import SwiftUI
import AVFoundation
import Translation
import Speech
import Combine

// ==========================================
// 1. リモコン（音量ボタン）の監視役
// ==========================================
@MainActor
class VolumeObserver: ObservableObject {
    @Published var volume: Float = 0.0
    private var observation: NSKeyValueObservation?
    
    init() {
        let session = AVAudioSession.sharedInstance()
        self.volume = session.outputVolume
        do { try session.setActive(true) } catch { print("Audio Session error") }
        
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let newVolume = session.outputVolume
            DispatchQueue.main.async { self?.volume = newVolume }
        }
    }
}

// ==========================================
// 2. 音声認識エンジン
// ==========================================
@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    func startTranscribing(language: String) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        
        task?.cancel()
        task = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { print("Audio setup error: \(error)") }
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        request.shouldReportPartialResults = true
        
        // ★ これを追加：AIに文脈を深く推測させ、句読点を自動で打たせる（iOS 16以降）
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            self.isRecording = true
            self.transcript = ""
        } catch { return }
        
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self.stopTranscribing()
            }
        }
    }
    
    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
    }
}

// ==========================================
// 3. メッセージデータの構造体（★相手からの受信にも対応）
// ==========================================
struct ChatMessage: Identifiable {
    let id = UUID()
    let originalText: String
    var translatedText: String
    var isTranslating: Bool
    var targetLanguage: String
    var isMine: Bool           // ★ 自分か相手か
    var senderName: String     // ★ 誰が送ったか
    var senderGender: String   // ★ 相手の性別
}

// ==========================================
// 4. メイン画面（ChatView）
// ==========================================
struct ChatView: View {
    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    
    @AppStorage("myLanguage") var myLanguage: String = "system"
    @AppStorage("secondName") var secondName: String = ""
    @AppStorage("myGender") var myGender: String = "female"
    
    @State private var targetLanguage: String = "en-US"
    @State private var showingSettings = false
    
    let languageList = [
        ("🇺🇸 英語 (米国)", "en-US"), ("🇬🇧 英語 (英国)", "en-GB"),
        ("🇨🇳 中国語", "zh-CN"), ("🇰🇷 韓国語", "ko-KR"),
        ("🇪🇸 スペイン語", "es-ES"), ("🇫🇷 フランス語", "fr-FR"), ("🇹🇭 タイ語", "th-TH"),
        ("🇯🇵 日本語", "ja-JP")
    ]
    
    @State private var isPocketMode: Bool = false
    @State private var birdRotation: Double = 0.0
    @State private var birdOffset: CGFloat = 0.0
    
    private let synthesizer = AVSpeechSynthesizer()
    @StateObject private var volumeObserver = VolumeObserver()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var connectionManager = ConnectionManager()
    
    @State private var isNetworking: Bool = false
    @State private var clickCount: Int = 0
    @State private var clickTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            VStack {
                // ーーー ヘッダー ーーー
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("相手の言語").font(.caption).foregroundColor(.secondary)
                        Picker("相手の言語", selection: $targetLanguage) {
                            ForEach(languageList, id: \.1) { language in Text(language.0).tag(language.1) }
                        }
                        .pickerStyle(MenuPickerStyle()).tint(.green).background(Color.green.opacity(0.1)).cornerRadius(8)
                    }
                    Spacer()
                    Button(action: {
                        isNetworking.toggle()
                        if isNetworking {
                            connectionManager.startNetworking()
                            AudioServicesPlaySystemSound(1110)
                        } else {
                            connectionManager.stopNetworking()
                            AudioServicesPlaySystemSound(1111)
                        }
                    }) {
                        Image(systemName: isNetworking ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .padding(10)
                            .background(isNetworking ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(20)
                            .foregroundColor(isNetworking ? .green : .gray)
                    }
                    
                    Button(action: { isPocketMode = true }) {
                        Image(systemName: "lock.fill").padding(10).background(Color.gray.opacity(0.2)).cornerRadius(20).foregroundColor(.primary)
                    }
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill").padding(10).background(Color.blue.opacity(0.1)).cornerRadius(20).foregroundColor(.blue)
                    }
                }.padding()
                
                // ーーー 履歴表示 ーーー
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            ForEach($messages) { $message in
                                ChatMessageRow(message: $message, synthesizer: synthesizer).id(message.id)
                            }
                        }.padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastId = messages.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }
                
                Spacer()
                
                // ーーー 入力エリア ーーー
                VStack(spacing: 15) {
                    if speechRecognizer.isRecording {
                        ScrollView {
                            Text(speechRecognizer.transcript.isEmpty ? "お話しください..." : speechRecognizer.transcript)
                                .foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        .frame(height: 80).background(Color.red.opacity(0.1)).cornerRadius(12)
                    } else {
                        TextField("手動で入力...", text: $inputText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { if !inputText.isEmpty { sendMessage(text: inputText); inputText = "" } }
                    }
                    
                    Button(action: { handleActionPress() }) {
                        HStack {
                            Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                            Text(speechRecognizer.isRecording ? "録音完了 (送信)" : "音声入力").fontWeight(.bold)
                        }.foregroundColor(.white).frame(maxWidth: .infinity).padding().background(speechRecognizer.isRecording ? Color.red : Color.blue).cornerRadius(12)
                    }
                }.padding().background(Color(UIColor.systemGray6))
            }
            .onChange(of: volumeObserver.volume) { _, _ in handleActionPress() }
            // ★ 新規追加：相手からメッセージとメタデータを受信した時の処理
            .onChange(of: connectionManager.receivedPayload?.id) { _, _ in
                if let payload = connectionManager.receivedPayload {
                    receiveMessage(payload)
                }
            }
            .sheet(isPresented: $showingSettings) { ProfileSettingsView() }
            
            if isPocketMode { pocketOverlay }
        }
    }
    
    // ==========================================
    // アクション・関数群
    // ==========================================
    func handleActionPress() {
        clickCount += 1
        clickTask?.cancel()
        
        clickTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                
                let currentClicks = clickCount
                clickCount = 0
                
                await MainActor.run {
                    if currentClicks == 1 {
                        if speechRecognizer.isRecording {
                            finishAndSend()
                        } else {
                            startRecording()
                        }
                    } else if currentClicks >= 2 {
                        if speechRecognizer.isRecording {
                            cancelRecording()
                        } else {
                            print("待機中のダブルクリック")
                        }
                    }
                }
            } catch { }
        }
    }
    
    func startRecording() {
        AudioServicesPlaySystemSound(1113)
        let actualLanguage = (myLanguage == "system") ? Locale.current.identifier : myLanguage
        speechRecognizer.startTranscribing(language: actualLanguage)
    }
    
    func finishAndSend() {
        speechRecognizer.stopTranscribing()
        let finalTranscript = speechRecognizer.transcript
        
        if finalTranscript.contains("ボイクリ") { cancelRecording(); return }
        
        AudioServicesPlaySystemSound(1052)
        if !finalTranscript.isEmpty { sendMessage(text: finalTranscript) }
        speechRecognizer.transcript = ""
    }
    
    func cancelRecording() {
        speechRecognizer.stopTranscribing()
        AudioServicesPlaySystemSound(1053)
        let utterance = AVSpeechUtterance(string: "ボイクリしました")
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
        speechRecognizer.transcript = ""
    }
    
    // ★ 自分が送信する時（メタデータも一緒に相手へ送る）
    func sendMessage(text: String) {
        let actualMyLanguage = (myLanguage == "system") ? Locale.current.identifier : myLanguage
        let isSameLanguage = (actualMyLanguage.prefix(2) == targetLanguage.prefix(2))
        
        // 1. 自分の画面に表示
        let newMessage = ChatMessage(
            originalText: text, translatedText: isSameLanguage ? text : "翻訳中...",
            isTranslating: !isSameLanguage, targetLanguage: targetLanguage,
            isMine: true, senderName: secondName, senderGender: myGender
        )
        messages.append(newMessage)
        
        // 2. 相手にテキストとメタデータを送信
        connectionManager.sendMessage(text: text, myName: secondName, myGender: myGender, myLanguage: actualMyLanguage)
    }
    
    // ★ 相手から受信した時（メタデータを受け取って表示）
    func receiveMessage(_ payload: ChatPayload) {
        let actualMyLanguage = (myLanguage == "system") ? Locale.current.identifier : myLanguage
        let isSameLanguage = (actualMyLanguage.prefix(2) == payload.senderLanguage.prefix(2))
        
        let incomingMessage = ChatMessage(
            originalText: payload.text,
            translatedText: isSameLanguage ? payload.text : "翻訳中...",
            isTranslating: !isSameLanguage,
            targetLanguage: actualMyLanguage, // 自分の言語に翻訳する
            isMine: false,
            senderName: payload.senderName, // ★ 相手の名前
            senderGender: payload.senderGender // ★ 相手の性別
        )
        messages.append(incomingMessage)
    }
    
    var pocketOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 40) {
                Spacer()
                VStack(spacing: 10) {
                    Text("VoxArk").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(Color(white: 0.3))
                    Text("ポケットモード動作中...").font(.headline).foregroundColor(Color(white: 0.4))
                }
                Image(systemName: "bird.fill").resizable().scaledToFit().frame(width: 60, height: 60).foregroundColor(Color(white: 0.3)).rotation3DEffect(.degrees(birdRotation), axis: (x: 0, y: 1, z: 0)).offset(y: birdOffset).onAppear { startBirdAnimation() }
                Spacer()
                VStack(spacing: 5) {
                    Image(systemName: "hand.tap.fill").foregroundColor(Color(white: 0.4))
                    Text("解除するには画面を3秒間長押ししてください").font(.footnote).foregroundColor(Color(white: 0.4))
                }.padding(.bottom, 50)
            }
        }.onLongPressGesture(minimumDuration: 3.0) {
            AudioServicesPlaySystemSound(1052)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            isPocketMode = false
        }
    }
    func startBirdAnimation() {
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { birdRotation = 40.0 }
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if isPocketMode {
                withAnimation(.interpolatingSpring(stiffness: 100, damping: 10)) { birdOffset = -20 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.interpolatingSpring(stiffness: 100, damping: 10)) { birdOffset = 0 }
                }
            }
        }
    }
}

// ==========================================
// 5. 吹き出しUI（★自分と相手で左右に振り分け）
// ==========================================
struct ChatMessageRow: View {
    @Binding var message: ChatMessage
    let synthesizer: AVSpeechSynthesizer
    @State private var translationConfig: TranslationSession.Configuration?
    
    var body: some View {
        HStack {
            if message.isMine { Spacer() } // 自分なら右寄せ
            
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                // 名前表示
                Text(message.senderName)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(message.isMine ? .trailing : .leading, 4)
                
                // 原文
                Text(message.originalText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                HStack(alignment: .bottom, spacing: 10) {
                    if !message.isMine && !message.isTranslating {
                        // 相手のメッセージ用：再生ボタンを左に
                        Button(action: { speak(text: message.translatedText, language: message.targetLanguage) }) {
                            Image(systemName: "speaker.wave.2.circle.fill").resizable().frame(width: 24, height: 24).foregroundColor(.blue)
                        }.padding(.bottom, 4)
                    }
                    
                    // 翻訳テキストの吹き出し
                    Text(message.translatedText)
                        .font(.body)
                        .padding(12)
                        .background(message.isMine ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .cornerRadius(12)
                        .contextMenu {
                            Button(action: { UIPasteboard.general.string = message.originalText }) { Text("原文をコピー"); Image(systemName: "doc.on.doc") }
                            Button(action: { UIPasteboard.general.string = message.translatedText }) { Text("翻訳をコピー"); Image(systemName: "doc.on.doc.fill") }
                        }
                    
                    if message.isMine && !message.isTranslating {
                        // 自分のメッセージ用：再生ボタンを右に
                        Button(action: { speak(text: message.translatedText, language: message.targetLanguage) }) {
                            Image(systemName: "speaker.wave.2.circle.fill").resizable().frame(width: 24, height: 24).foregroundColor(.green)
                        }.padding(.bottom, 4)
                    }
                }
            }
            .padding(.leading, message.isMine ? 50 : 0)
            .padding(.trailing, message.isMine ? 0 : 50)
            
            if !message.isMine { Spacer() } // 相手なら左寄せ
        }
        .onAppear {
            if message.isTranslating {
                let targetLocale = Locale.Language(identifier: message.targetLanguage)
                translationConfig = TranslationSession.Configuration(target: targetLocale)
            } else {
                speak(text: message.originalText, language: message.targetLanguage)
            }
        }
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(message.originalText)
                DispatchQueue.main.async {
                    message.translatedText = response.targetText
                    message.isTranslating = false
                    speak(text: response.targetText, language: message.targetLanguage)
                }
            } catch {
                DispatchQueue.main.async { message.translatedText = "翻訳エラー"; message.isTranslating = false }
            }
        }
    }
    
    // ★ 送信者のジェンダー（メタデータ）を使ってSiriの声を決定
    func speak(text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        let targetGender: AVSpeechSynthesisVoiceGender = (message.senderGender == "male") ? .male : .female
        
        if let premiumVoice = allVoices.first(where: { $0.language == language && $0.gender == targetGender && $0.quality == .premium }) {
            utterance.voice = premiumVoice
        } else if let enhancedVoice = allVoices.first(where: { $0.language == language && $0.gender == targetGender && $0.quality == .enhanced }) {
            utterance.voice = enhancedVoice
        } else if let defaultVoice = allVoices.first(where: { $0.language == language && $0.gender == targetGender }) {
            utterance.voice = defaultVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        synthesizer.speak(utterance)
    }
}

