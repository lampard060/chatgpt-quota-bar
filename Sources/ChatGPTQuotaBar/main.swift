import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let client = QuotaRPCClient()
    private let statusFormatter = QuotaStatusFormatter()
    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var snapshot: QuotaSnapshot?
    private var lastUpdated: Date?
    private var lastError: String?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.toolTip = "ChatGPT / Codex 剩余额度"
        render()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.bundleIdentifier == "com.openai.codex" else { return }
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    @objc private func refreshMenuItemSelected() {
        refresh()
    }

    @objc private func openChatGPT() {
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            workspace.openApplication(
                at: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        render()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.client.fetch() }
            DispatchQueue.main.async {
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.lastUpdated = Date()
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
                self.render()
            }
        }
    }

    private func render() {
        renderStatusTitle()
        let menu = NSMenu()

        if let snapshot {
            menu.addItem(disabledItem("ChatGPT \(displayPlan(snapshot.planType))"))
            menu.addItem(.separator())
            menu.addItem(disabledItem(windowText(name: "5 小时窗口", window: snapshot.primary)))
            menu.addItem(disabledItem(windowText(name: "7 天窗口", window: snapshot.secondary)))

            if let credits = snapshot.credits {
                let balance = credits.unlimited ? "不限" : (credits.balance ?? "0")
                let resetCount = snapshot.resetCreditCount ?? 0
                menu.addItem(disabledItem("额外积分：\(balance)  ·  重置券：\(resetCount)"))
            }
        } else {
            menu.addItem(disabledItem("正在读取 ChatGPT 额度…"))
        }

        if let lastError {
            menu.addItem(.separator())
            menu.addItem(disabledItem("读取失败：\(lastError)"))
        }

        menu.addItem(.separator())
        if let lastUpdated {
            menu.addItem(disabledItem("更新于 \(timeFormatter.string(from: lastUpdated)) · 每分钟自动刷新"))
        } else {
            menu.addItem(disabledItem("每分钟自动刷新"))
        }
        menu.addItem(actionItem(isRefreshing ? "正在刷新…" : "立即刷新", #selector(refreshMenuItemSelected), enabled: !isRefreshing))
        menu.addItem(actionItem("打开 ChatGPT", #selector(openChatGPT)))
        menu.addItem(.separator())
        menu.addItem(disabledItem("数据来自本机 ChatGPT 只读额度接口"))
        menu.addItem(actionItem("退出额度显示", #selector(quit)))
        statusItem.menu = menu
    }

    private func renderStatusTitle() {
        let title: String
        var color = NSColor.labelColor

        if let snapshot,
           let formattedTitle = statusFormatter.title(for: snapshot),
           let primary = snapshot.primary?.remainingPercent,
           let secondary = snapshot.secondary?.remainingPercent {
            title = formattedTitle
            let lowest = min(primary, secondary)
            if lowest <= 15 {
                color = .systemRed
            } else if lowest <= 30 {
                color = .systemOrange
            }
        } else {
            title = isRefreshing ? "额度 …" : "额度 —"
            color = .secondaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func windowText(name: String, window: QuotaWindow?) -> String {
        guard let window else { return "\(name)：暂无数据" }
        let resetText = window.resetsAt.map { resetFormatter.string(from: $0) } ?? "时间未知"
        return "\(name)：剩余 \(window.remainingPercent)%  ·  \(resetText) 重置"
    }

    private func displayPlan(_ plan: String?) -> String {
        guard let plan, !plan.isEmpty else { return "账号" }
        return plan.prefix(1).uppercased() + plan.dropFirst()
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private lazy var resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
