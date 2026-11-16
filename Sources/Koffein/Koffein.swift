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

/// MenuBarExtra's window has 16pt corners (measured on macOS 27). Shapes inset from its edge use this minus the inset, so they stay concentric.
let panelRadius: CGFloat = 16
/// Every row's content starts this far from the panel's edge.
let gutter: CGFloat = 14

struct KoffeinMenu: View {
    @ObservedObject var koffein: Koffein
    private let durations = [(0, ""), (15, "15 min"), (30, "30 min"), (60, "1 hr"), (240, "4 hrs"), (480, "8 hrs")]

    private var status: String {
        guard koffein.isActive else { return "Off" }
        return koffein.endDate.map { "Until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Indefinitely"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { koffein.isActive ? koffein.stop() : koffein.start() }
                } label: {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(koffein.isActive ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Otherwise it takes keyboard focus when the menu opens, so Space switches Koffein off.
                .focusable(false)
                .glassEffect(koffein.isActive ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)
                .accessibilityLabel("Koffein")
                .accessibilityValue(koffein.isActive ? "On" : "Off")
                .accessibilityAddTraits(.isToggle)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Koffein").font(.headline)
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Only the selected chip is glass: glass on the glass panel muddies both.
            GlassEffectContainer {
                HStack(spacing: 4) {
                    ForEach(durations, id: \.0) { minutes, label in
                        let isSelected = minutes == koffein.minutes
                        Button {
                            withAnimation(.spring(duration: 0.35, bounce: 0)) { koffein.minutes = minutes }
                        } label: {
                            Group {
                                if minutes == 0 {
                                    Image(systemName: "infinity").font(.system(size: 12, weight: .semibold)).accessibilityLabel("Indefinitely")
                                } else {
                                    Text(label)
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .fixedSize()
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Capsule())
                            .background(isSelected ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary), in: Capsule())
                            .glassEffect(isSelected ? .regular.tint(.accentColor).interactive() : .identity, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, gutter)

            MenuDivider().padding(.top, 6)

            SettingRow(icon: "power", color: .gray, title: "Open at Login", isOn: $koffein.opensAtLogin)
            SettingRow(icon: "bolt.fill", color: .orange, title: "Activate on Launch", isOn: $koffein.activatesAtLaunch)
            SettingRow(icon: "moon.fill", color: .indigo, title: "Allow Display Sleep", isOn: $koffein.allowsDisplaySleep)

            MenuDivider()

            MenuButton(title: "Quit Koffein") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.top, 6)
        .frame(width: 320)
        .toggleStyle(.switch)
    }
}

struct SettingRow: View {
    let icon: String
    let color: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, gutter)
        .frame(minHeight: 32)
    }
}

/// The last row, so its hover sits in the panel's bottom corners: same inset on every side, radius concentric with the panel.
struct MenuButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    private let inset: CGFloat = 6

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.horizontal, gutter - inset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Otherwise it takes keyboard focus when the menu opens, so Return or Space quits the app.
        .focusable(false)
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: panelRadius - inset, style: .continuous))
        .onHover { isHovered = $0 }
        .padding(inset)
    }
}

struct MenuDivider: View {
    var body: some View { Divider().padding(.horizontal, gutter).padding(.vertical, 5) }
}

@main struct KoffeinApp: App {
    @StateObject private var koffein = Koffein()

    var body: some Scene {
        MenuBarExtra {
            KoffeinMenu(koffein: koffein)
        } label: {
            // MenuBarExtra drops .accessibilityLabel, so VoiceOver only hears the description baked into the NSImage.
            Image(nsImage: NSImage(systemSymbolName: koffein.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: koffein.isActive ? "Koffein, on" : "Koffein, off")!)
        }
        .menuBarExtraStyle(.window)
    }
}
