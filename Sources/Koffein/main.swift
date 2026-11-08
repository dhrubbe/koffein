import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import SwiftUI

@MainActor final class Koffein: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published var minutes: Int { didSet { defaults.set(minutes, forKey: "minutes"); if isActive { scheduleEnd() } } }
    @Published var activatesAtLaunch: Bool { didSet { defaults.set(activatesAtLaunch, forKey: "activatesAtLaunch") } }
    @Published var allowsDisplaySleep: Bool {
        didSet { defaults.set(allowsDisplaySleep, forKey: "allowsDisplaySleep"); if isActive, !assertPower() { stop() } }
    }
    private let defaults = UserDefaults.standard
    private var assertion = IOPMAssertionID(0)
    private var timer: Timer?

    init() {
        defaults.register(defaults: ["activatesAtLaunch": true])
        minutes = defaults.integer(forKey: "minutes")
        activatesAtLaunch = defaults.bool(forKey: "activatesAtLaunch")
        allowsDisplaySleep = defaults.bool(forKey: "allowsDisplaySleep")
        if !defaults.bool(forKey: "didSetUpLoginItem") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didSetUpLoginItem")
        }
        if activatesAtLaunch { start() }
        // Timers run on uptime, which stops during sleep, so re-check the deadline against the clock on wake.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.armTimer() }
        }
    }

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do { try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch { NSSound.beep() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    func start() {
        guard assertPower() else { NSSound.beep(); return }
        isActive = true
        scheduleEnd()
    }

    func stop() {
        timer?.invalidate(); timer = nil; endDate = nil
        releasePower()
        isActive = false
    }

    // An IOKit assertion dies with the process, so quitting or crashing never leaves the Mac stuck awake.
    private func assertPower() -> Bool {
        releasePower()
        let type = allowsDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        return IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Koffein" as CFString, &assertion) == kIOReturnSuccess
    }

    private func releasePower() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }

    private func scheduleEnd() {
        endDate = minutes > 0 ? Date.now.addingTimeInterval(TimeInterval(minutes * 60)) : nil
        armTimer()
    }

    private func armTimer() {
        timer?.invalidate(); timer = nil
        guard let endDate else { return }
        guard endDate > .now else { return stop() }
        timer = Timer.scheduledTimer(withTimeInterval: endDate.timeIntervalSinceNow, repeats: false) { [weak self] _ in Task { @MainActor in self?.stop() } }
    }
}

struct KoffeinMenu: View {
    @ObservedObject var koffein: Koffein
    private let durations = [(0, ""), (15, "15 min"), (30, "30 min"), (60, "1 h"), (240, "4 h"), (480, "8 h")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Koffein").font(.headline)
                    if let endDate = koffein.endDate {
                        Text("Stängs av \(endDate.formatted(date: .omitted, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Koffein", isOn: Binding(get: { koffein.isActive }, set: { $0 ? koffein.start() : koffein.stop() }))
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)

            MenuDivider()

            DurationPicker(minutes: $koffein.minutes, options: durations)
                .padding(.horizontal, 14)
            .padding(.vertical, 4)

            MenuDivider()

            SettingRow(title: "Öppna vid inloggning", isOn: $koffein.opensAtLogin)
            SettingRow(title: "Aktivera vid start", isOn: $koffein.activatesAtLaunch)
            SettingRow(title: "Låt skärmen gå i vila", isOn: $koffein.allowsDisplaySleep)

            MenuDivider()

            MenuButton(title: "Avsluta Koffein") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.vertical, 6)
        .frame(width: 320)
        .toggleStyle(.switch)
    }
}

// SwiftUI's segmented Picker can settle on equal-width segments wider than the menu and push everything
// off the left edge, so the AppKit control is sized to exactly the width it is offered.
struct DurationPicker: NSViewRepresentable {
    @Binding var minutes: Int
    let options: [(Int, String)]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map { $0.1 }, trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.segmentDistribution = .fillProportionally
        if let index = options.firstIndex(where: { $0.0 == 0 }) {
            control.setImage(NSImage(systemSymbolName: "infinity", accessibilityDescription: "Tills vidare"), forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = options.firstIndex { $0.0 == minutes } ?? -1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? control.fittingSize.width, height: control.fittingSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: DurationPicker
        init(_ parent: DurationPicker) { self.parent = parent }
        @objc func select(_ control: NSSegmentedControl) { parent.minutes = parent.options[control.selectedSegment].0 }
    }
}

struct SettingRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 28)
    }
}

struct MenuButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Otherwise it takes keyboard focus when the menu opens, so Return or Space quits the app.
        .focusable(false)
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
        .padding(.horizontal, 5)
    }
}

struct MenuDivider: View {
    var body: some View { Divider().padding(.horizontal, 14).padding(.vertical, 5) }
}

@main struct KoffeinApp: App {
    @StateObject private var koffein = Koffein()

    var body: some Scene {
        MenuBarExtra {
            KoffeinMenu(koffein: koffein)
        } label: {
            // MenuBarExtra drops .accessibilityLabel, so VoiceOver only hears the description baked into the NSImage.
            Image(nsImage: NSImage(systemSymbolName: koffein.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: koffein.isActive ? "Koffein, på" : "Koffein, av")!)
        }
        .menuBarExtraStyle(.window)
    }
}
