import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private let backend = BackendClient()
    private let backendProcess = BackendProcessManager()
    private let injector = TextInjector()
    private var hotkey: HotkeyController?
    private var stateItem = NSMenuItem(title: "● Starting", action: nil, keyEquivalent: "")
    private var selectedText: String?
    private var isListening = false
    private var hotkeyReady = false
    private var recordingWatchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        requestAccessibilityPermission()
        backendProcess.startIfNeeded()

        let hotkey = HotkeyController(
            pressed: { [weak self] in self?.beginListening() },
            released: { [weak self] in self?.finishListening() }
        )
        self.hotkey = hotkey
        do {
            try hotkey.install()
            hotkeyReady = true
        } catch {
            hotkeyReady = false
            updateState(
                "● Hotkey Error",
                error: "请授予 VoiceForge 输入监控与辅助功能权限并重新启动。"
            )
        }

        waitForBackend(attemptsRemaining: 20)
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingWatchdog?.invalidate()
        backendProcess.stopOwnedProcess()
    }

    private func configureMenu() {
        statusItem.button?.title = "🎙 VoiceForge"
        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        let shortcut = NSMenuItem(
            title: "按住 ⌘⇧Space 讲话",
            action: nil,
            keyEquivalent: ""
        )
        shortcut.isEnabled = false
        menu.addItem(shortcut)

        let asr = NSMenuItem(
            title: "ASR：SenseVoiceSmall（本地）",
            action: nil,
            keyEquivalent: ""
        )
        asr.isEnabled = false
        menu.addItem(asr)

        let language = NSMenuItem(
            title: "语言：中文",
            action: nil,
            keyEquivalent: ""
        )
        language.isEnabled = false
        menu.addItem(language)
        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "打开设置文件",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "运行环境诊断",
                action: #selector(runDoctor),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "打开数据目录",
                action: #selector(openDataDirectory),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出 VoiceForge",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func requestAccessibilityPermission() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [prompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func waitForBackend(attemptsRemaining: Int) {
        backend.health { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if self?.hotkeyReady == true {
                        self?.updateState("● Ready")
                    }
                case .failure(let error):
                    guard attemptsRemaining > 0 else {
                        self?.updateState(
                            "● Backend Error",
                            error: error.localizedDescription
                        )
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.waitForBackend(attemptsRemaining: attemptsRemaining - 1)
                    }
                }
            }
        }
    }

    private func beginListening() {
        guard !isListening else { return }
        selectedText = TextInjector.currentSelection()
        updateState("● Listening")
        recordingWatchdog?.invalidate()
        recordingWatchdog = Timer.scheduledTimer(
            withTimeInterval: 120,
            repeats: false
        ) { [weak self] _ in
            self?.finishListening()
        }
        backend.startRecording { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isListening = true
                case .failure(let error):
                    self?.isListening = false
                    self?.recordingWatchdog?.invalidate()
                    self?.recordingWatchdog = nil
                    self?.updateState(
                        "● Record Error",
                        error: error.localizedDescription
                    )
                }
            }
        }
    }

    private func finishListening() {
        guard isListening else { return }
        isListening = false
        recordingWatchdog?.invalidate()
        recordingWatchdog = nil
        updateState("● Processing")
        backend.stopRecording(selectedText: selectedText) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let response):
                    do {
                        let application = NSWorkspace.shared
                            .frontmostApplication?.localizedName ?? ""
                        try self.injector.inject(response.text)
                        self.backend.acknowledgeInjection(
                            response: response,
                            application: application
                        )
                        self.updateState("● Ready")
                    } catch {
                        self.updateState(
                            "● Inject Error",
                            error: error.localizedDescription
                        )
                    }
                case .failure(let error):
                    let message = error.localizedDescription
                    self.updateState(
                        self.processingErrorTitle(for: message),
                        error: message
                    )
                }
            }
        }
    }

    private func processingErrorTitle(for message: String) -> String {
        if message.contains("时间过短") {
            return "● 录音时间过短"
        }
        if message.contains("音量过低") || message.contains("几乎没有声音") {
            return "● 录音音量过低"
        }
        if message.contains("未采集到音频") {
            return "● 未采集到音频"
        }
        if message.contains("未识别到清晰语音")
            || message.contains("没有识别到文字")
        {
            return "● 未识别到语音"
        }
        return "● 语音处理失败"
    }

    private func updateState(_ title: String, error: String? = nil) {
        stateItem.title = title
        statusItem.button?.title = title == "● Ready"
            ? "🎙 VoiceForge"
            : "🎙 \(title.replacingOccurrences(of: "● ", with: ""))"
        if let error {
            statusItem.button?.toolTip = error
        } else {
            statusItem.button?.toolTip = "按住 ⌘⇧Space 讲话"
        }
    }

    @objc private func openSettings() {
        guard let root = backendProcess.projectRoot else { return }
        let path = root.appendingPathComponent(".env")
        if !FileManager.default.fileExists(atPath: path.path) {
            let example = root.appendingPathComponent(".env.example")
            try? FileManager.default.copyItem(at: example, to: path)
        }
        NSWorkspace.shared.open(path)
    }

    @objc private func openDataDirectory() {
        guard let root = backendProcess.projectRoot else { return }
        let path = root.appendingPathComponent("data", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: path,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(path)
    }

    @objc private func runDoctor() {
        backendProcess.runDoctor { output in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "VoiceForge 环境诊断"
                alert.informativeText = output
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }
}
