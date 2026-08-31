import AppKit
import Foundation

private final class QuotaProgressView: NSView {
    private let percentage: Int
    private let fillColor: NSColor

    init(percentage: Int, fillColor: NSColor) {
        self.percentage = percentage
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = bounds.insetBy(dx: 0, dy: 1)
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()

        let width = track.width * CGFloat(max(0, min(100, percentage))) / 100
        guard width > 0 else { return }
        let fill = NSRect(x: track.minX, y: track.minY, width: width, height: track.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }
}

private final class QuotaMenuCardView: NSView {
    private static let width: CGFloat = 324
    // The card contains two quota sections, two account rows, and three actions.
    // Keep it tall enough so the reset-credit row is never compressed out of view.
    private static let height: CGFloat = 436

    init(
        snapshot: QuotaSnapshot?,
        lastUpdated: Date?,
        lastError: String?,
        isRefreshing: Bool,
        target: AnyObject,
        refreshAction: Selector,
        openAction: Selector,
        quitAction: Selector
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        // NSMenu resolves dynamic NSColor values before the custom view has a
        // window in some macOS dark-mode configurations. That can turn the
        // card background white while resolving labels as white as well.
        // Keep the card's own palette explicitly light so it remains readable
        // regardless of the system appearance used by the menu bar.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 17, left: 18, bottom: 14, right: 18)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let heading = textLabel("额度概览", size: 16, weight: .semibold, color: .labelColor)
        content.addArrangedSubview(heading)

        if let snapshot {
            let plan = "ChatGPT \(displayPlan(snapshot.planType))"
            content.addArrangedSubview(textLabel(plan, size: 12, weight: .medium, color: .secondaryLabelColor))
            content.addArrangedSubview(windowSection(
                name: "5 小时额度",
                resetName: "重置时间",
                window: snapshot.primary,
                resetFormat: .time
            ))
            content.addArrangedSubview(separator())
            content.addArrangedSubview(windowSection(
                name: "周额度",
                resetName: "重置日期",
                window: snapshot.secondary,
                resetFormat: .date
            ))
            content.addArrangedSubview(separator())

            let credits = snapshot.credits
            let balance = credits?.unlimited == true ? "不限" : (credits?.balance ?? "—")
            let resetCount = snapshot.resetCreditCount.map { "\($0) 张" } ?? "—"
            content.addArrangedSubview(infoRow("额外积分", value: balance))
            content.addArrangedSubview(infoRow("重置券", value: resetCount))
            content.addArrangedSubview(infoRow("最早到期", value: earliestResetCreditExpiry(in: snapshot)))
        } else {
            content.addArrangedSubview(textLabel(
                lastError.map { "读取失败：\($0)" } ?? "正在读取 ChatGPT 额度…",
                size: 13,
                weight: .regular,
                color: lastError == nil ? .secondaryLabelColor : .systemRed
            ))
            content.addArrangedSubview(expandingSpacer())
        }

        content.addArrangedSubview(separator())
        let updateText = lastUpdated.map { "更新于 \(Self.timeFormatter.string(from: $0))" } ?? "每分钟自动刷新"
        content.addArrangedSubview(textLabel(updateText, size: 11, weight: .regular, color: .tertiaryLabelColor))
        content.addArrangedSubview(actionButton(
            title: isRefreshing ? "正在刷新…" : "立即刷新",
            symbol: "arrow.clockwise",
            target: target,
            action: refreshAction,
            enabled: !isRefreshing
        ))
        content.addArrangedSubview(actionButton(
            title: "打开 ChatGPT",
            symbol: "arrow.up.forward.app",
            target: target,
            action: openAction
        ))
        content.addArrangedSubview(actionButton(
            title: "退出额度显示",
            symbol: "power",
            target: target,
            action: quitAction,
            destructive: true
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.height)
    }

    private func windowSection(
        name: String,
        resetName: String,
        window: QuotaWindow?,
        resetFormat: ResetFormat
    ) -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6

        guard let window else {
            section.addArrangedSubview(textLabel("\(name)：暂无数据", size: 13, weight: .medium, color: .secondaryLabelColor))
            return section
        }

        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.distribution = .fill
        heading.addArrangedSubview(textLabel(name, size: 14, weight: .medium, color: .labelColor))
        heading.addArrangedSubview(expandingSpacer())
        heading.addArrangedSubview(textLabel(
            "\(window.remainingPercent)%",
            size: 16,
            weight: .semibold,
            color: quotaColor(for: window.remainingPercent)
        ))
        section.addArrangedSubview(heading)

        let progress = QuotaProgressView(
            percentage: window.remainingPercent,
            fillColor: quotaColor(for: window.remainingPercent)
        )
        progress.translatesAutoresizingMaskIntoConstraints = false
        let progressContainer = NSView()
        progressContainer.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            progress.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            progress.heightAnchor.constraint(equalToConstant: 7),
            progressContainer.widthAnchor.constraint(equalToConstant: 288),
            progressContainer.heightAnchor.constraint(equalToConstant: 9),
        ])
        section.addArrangedSubview(progressContainer)

        let resetText: String
        if let date = window.resetsAt {
            resetText = resetFormat == .time ? Self.timeFormatter.string(from: date) : Self.dateFormatter.string(from: date)
        } else {
            resetText = "时间未知"
        }
        section.addArrangedSubview(infoRow(resetName, value: resetText, valueColor: .labelColor))
        return section
    }

    private func infoRow(_ title: String, value: String, valueColor: NSColor = .systemBlue) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.addArrangedSubview(textLabel(title, size: 13, weight: .regular, color: .secondaryLabelColor))
        row.addArrangedSubview(expandingSpacer())
        row.addArrangedSubview(textLabel(value, size: 13, weight: .medium, color: valueColor))
        row.widthAnchor.constraint(equalToConstant: 288).isActive = true
        return row
    }

    private func actionButton(
        title: String,
        symbol: String,
        target: AnyObject,
        action: Selector,
        enabled: Bool = true,
        destructive: Bool = false
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .texturedRounded
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.isEnabled = enabled
        button.contentTintColor = destructive ? .systemRed : .labelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.widthAnchor.constraint(equalToConstant: 288).isActive = true
        button.heightAnchor.constraint(equalToConstant: 25).isActive = true
        return button
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 288).isActive = true
        return line
    }

    private func expandingSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func textLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func quotaColor(for remainingPercent: Int) -> NSColor {
        if remainingPercent <= 15 { return .systemRed }
        if remainingPercent <= 30 { return .systemOrange }
        return .systemGreen
    }

    private func earliestResetCreditExpiry(in snapshot: QuotaSnapshot) -> String {
        let earliest = snapshot.resetCredits
            .filter { $0.status == "available" }
            .compactMap(\.expiresAt)
            .min()
        return earliest.map { Self.expiryFormatter.string(from: $0) } ?? "—"
    }

    private func displayPlan(_ plan: String?) -> String {
        guard let plan, !plan.isEmpty else { return "账号" }
        return plan.prefix(1).uppercased() + plan.dropFirst()
    }

    private enum ResetFormat { case time, date }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日（EEE）"
        return formatter
    }()

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

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
        let card = QuotaMenuCardView(
            snapshot: snapshot,
            lastUpdated: lastUpdated,
            lastError: lastError,
            isRefreshing: isRefreshing,
            target: self,
            refreshAction: #selector(refreshMenuItemSelected),
            openAction: #selector(openChatGPT),
            quitAction: #selector(quit)
        )
        let cardItem = NSMenuItem()
        cardItem.view = card
        menu.addItem(cardItem)
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

}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
