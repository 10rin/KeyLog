import SwiftUI
import Cocoa
import AVFoundation

// --- 1. データ保持用のモデル ---
struct KeyData {
    let keyCode: UInt16
    let volume: Float
}

// --- 2. 音量監視とデータ管理のロジック ---
class AppViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var resultsText = "Startを押して計測を開始してください"
    
    private var capturedData: [KeyData] = []
    private let engine = AVAudioEngine()
    private var volumeHistory: [Float] = Array(repeating: 0.0, count: 20)
    private var eventMonitor: Any?
    
    var currentRMS: Float {
        volumeHistory.max() ?? 0.0
    }

    func start() {
        capturedData = []
        isRunning = true
        resultsText = "計測中..."
        
        // マイク監視開始
        setupMicrophone()
        
        // キーイベント監視開始
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRunning else { return }
            
            // 音の到達を待つためにわずかに遅延させて記録
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let peak = self.currentRMS
                self.capturedData.append(KeyData(keyCode: event.keyCode, volume: peak))
                print("Captured: \(event.keyCode) at \(peak)")
            }
        }
    }

    func stop() {
        isRunning = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        
        analyzeResults()
        saveResultsToFile()
    }

    private func setupMicrophone() {
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self = self, let channelData = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channelDataArray = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
            let sumOfSquares = channelDataArray.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumOfSquares / Float(frames))
            
            DispatchQueue.main.async {
                self.volumeHistory.removeFirst()
                self.volumeHistory.append(rms)
            }
        }
        
        try? engine.start()
    }

    private func analyzeResults() {
        if capturedData.isEmpty {
            resultsText = "データが取得されませんでした"
            return
        }

        // 36は一般的なJISキーボードのEnterキーコード（モデルにより異なる場合があります）
        let enterKey: UInt16 = 36 
        
        let enterVolumes = capturedData.filter { $0.keyCode == enterKey }.map { $0.volume }
        let otherVolumes = capturedData.filter { $0.keyCode != enterKey }.map { $0.volume }

        let enterAvg = enterVolumes.isEmpty ? 0 : enterVolumes.reduce(0, +) / Float(enterVolumes.count)
        let otherAvg = otherVolumes.isEmpty ? 0 : otherVolumes.reduce(0, +) / Float(otherVolumes.count)

        // キーごとの平均音量を計算
        var keyAverages: [(keyCode: UInt16, average: Float, count: Int)] = []
        let uniqueKeyCodes = Set(capturedData.map { $0.keyCode })
        
        for keyCode in uniqueKeyCodes.sorted() {
            let volumes = capturedData.filter { $0.keyCode == keyCode }.map { $0.volume }
            let average = volumes.reduce(0, +) / Float(volumes.count)
            keyAverages.append((keyCode, average, volumes.count))
        }
        
        keyAverages.sort { $0.keyCode < $1.keyCode }
        
        // キーごとの詳細情報を作成
        let keyDetailsText = keyAverages.map { key in
            let keyName = getKeyName(keyCode: key.keyCode)
            return "\(keyName) (code: \(key.keyCode)): \(String(format: "%.5f", key.average)) [\(key.count)回]"
        }.joined(separator: "\n")

        resultsText = """
        【分析結果】
        合計打鍵数: \(capturedData.count) 回
        
        【カテゴリ別統計】
        Enterキー平均音量: \(String(format: "%.5f", enterAvg))
        その他キー平均音量: \(String(format: "%.5f", otherAvg))
        
        \(enterAvg > otherAvg ? "Enterの方が強打されています！" : "打鍵バランスは均等です。")
        
        【全キーの平均音量】
        \(keyDetailsText)
        """
    }
    
    private func getKeyName(keyCode: UInt16) -> String {
        let keyNames: [UInt16: String] = [
            // 数字キー
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            // QWERTY
            12: "Q", 13: "W", 14: "E", 15: "R", 17: "T", 16: "Y", 32: "U", 34: "I", 31: "O", 35: "P",
            // ASDFGH
            0: "A", 1: "S", 2: "D", 3: "F", 5: "G", 4: "H", 38: "J", 40: "K", 37: "L",
            // ZXCVBNM
            6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 45: "N", 46: "M",
            // 記号キー
            24: "+", 27: "-", 30: "]", 33: "[", 41: ";", 39: "'", 42: "\\", 43: ",", 47: ".", 44: "/",
            // スペースキー
            49: "Space",
            // 制御キー
            53: "Esc", 48: "Tab", 36: "Return(Enter)", 51: "Delete", 115: "Home", 119: "End",
            // 矢印キー
            123: "←", 124: "→", 125: "↓", 126: "↑",
            // その他
            50: "`", 57: "CapsLock", 56: "Shift", 60: "RShift", 55: "Cmd", 58: "Option", 61: "ROpt", 59: "Ctrl", 62: "RCtrl"
        ]
        return keyNames[keyCode] ?? "Key(\(keyCode))"
    }
    
    private func saveResultsToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["txt"]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "分析結果_\(timestamp).txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try self.resultsText.write(to: url, atomically: true, encoding: .utf8)
                    print("✓ ファイルが保存されました: \(url.path)")
                } catch {
                    print("✗ ファイル保存エラー: \(error)")
                }
            }
        }
    }
}

// --- 3. GUI (SwiftUI) ---
struct ContentView: View {
    @StateObject var vm = AppViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("実験")
                .font(.headline)
            
            HStack {
                Button(action: { vm.start() }) {
                    Text("Start")
                        .frame(width: 80)
                }
                .disabled(vm.isRunning)
                
                Button(action: { vm.stop() }) {
                    Text("End")
                        .frame(width: 80)
                }
                .disabled(!vm.isRunning)
            }
            
            Divider()
            
            ScrollView {
                Text(vm.resultsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 600, height: 700)
    }
}

// --- 4. アプリケーションの起動設定 ---
@main
struct KeyLog: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}