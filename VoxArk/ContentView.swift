import SwiftUI
import AVFoundation
import Translation
import NaturalLanguage

struct ChatMessage: Identifiable {
    let id = UUID()
    let originalText: String
    var translatedText: String
    var isTranslating: Bool
    var showOriginal: Bool = false
    var detectedLanguage: String = "en-US"
}

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    
    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        VStack {
            Text("VoxArk - 万能翻訳チャット")
                .font(.headline)
                .padding()
            
            // ーーー 履歴スクロールエリア ーーー
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach($messages) { $message in
                            MessageRow(message: $message, synthesizer: synthesizer)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            // ーーー 入力エリア ーーー
            HStack {
                TextField("外国語のテキストをペースト...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit { sendMessage() }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding()
        }
    }
    
    func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        var detectedLang = "en-US"
        if let recognizerLang = NLLanguageRecognizer.dominantLanguage(for: inputText) {
            detectedLang = recognizerLang.rawValue
        }
        
        let newMessage = ChatMessage(
            originalText: inputText,
            translatedText: "翻訳中...",
            isTranslating: true,
            detectedLanguage: detectedLang
        )
        
        messages.append(newMessage)
        inputText = ""
    }
}

// ーーー 1つの吹き出し（行） ーーー
struct MessageRow: View {
    @Binding var message: ChatMessage
    let synthesizer: AVSpeechSynthesizer
    @State private var translationConfig: TranslationSession.Configuration?
    
    var body: some View {
        HStack {
            // ★相手からのメッセージとして「左寄せ」に配置
            VStack(alignment: .leading, spacing: 8) {
                
                // 1. 翻訳されたテキストと再再生ボタン
                HStack(alignment: .bottom, spacing: 10) {
                    Text(message.translatedText)
                        .font(.body) // ★原文と同じフォントサイズに
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    
                    // ★日本語の再再生ボタン
                    if !message.isTranslating {
                        Button(action: {
                            speak(text: message.translatedText, language: "ja-JP")
                        }) {
                            Image(systemName: "speaker.wave.2.circle.fill")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.blue)
                        }
                        .padding(.bottom, 8)
                    }
                }
                
                // 2. 原文ボタン
                if !message.isTranslating {
                    Button(action: {
                        message.showOriginal.toggle()
                        if message.showOriginal {
                            speak(text: message.originalText, language: message.detectedLanguage)
                        }
                    }) {
                        Text(message.showOriginal ? "原文を隠す" : "原文を聴く")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                
                // 3. 原文テキスト
                if message.showOriginal {
                    Text(message.originalText)
                        .font(.body) // ★日本語と同じフォントサイズに
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: .leading)
            
            Spacer() // ★右側に余白を作って、左寄せを確定させる
        }
        .onAppear {
            if message.isTranslating {
                translationConfig = TranslationSession.Configuration()
            }
        }
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(message.originalText)
                DispatchQueue.main.async {
                    message.translatedText = response.targetText
                    message.isTranslating = false
                    // 最初の1回は自動で日本語読み上げ
                    speak(text: response.targetText, language: "ja-JP")
                }
            } catch {
                DispatchQueue.main.async {
                    message.translatedText = "翻訳エラー"
                    message.isTranslating = false
                }
            }
        }
    }
    
    func speak(text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }
}
