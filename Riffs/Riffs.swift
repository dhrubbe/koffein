// Design riffs for the Koffein menu, each on the same glass surface so they compare fairly.
// Run ./Riffs/run.sh to click around in them; ./Riffs/run.sh --capture <dir> writes PNGs and quits.
import AppKit
import SwiftUI

// MARK: - Fake model (no IOKit, same shape as Koffein)

@MainActor final class FakeKoffein: ObservableObject {
    @Published private(set) var isActive = true
    @Published private(set) var endDate: Date?
    @Published var minutes: Int { didSet { if isActive { schedule() } } }
    @Published var opensAtLogin = true
    @Published var activatesAtLaunch = true
    @Published var allowsDisplaySleep = false

    init(minutes: Int) { self.minutes = minutes; schedule() }

    func start() { isActive = true; schedule() }
    func stop() { isActive = false; endDate = nil }
    func toggle() { isActive ? stop() : start() }
    private func schedule() { endDate = isActive && minutes > 0 ? Date.now.addingTimeInterval(TimeInterval(minutes * 60)) : nil }

    var activeBinding: Binding<Bool> { Binding(get: { self.isActive }, set: { $0 ? self.start() : self.stop() }) }
    var endText: String? { endDate.map { "Stängs av \($0.formatted(date: .omitted, time: .shortened))" } }
}

let durations = [(0, ""), (15, "15 min"), (30, "30 min"), (60, "1 h"), (240, "4 h"), (480, "8 h")]

// MARK: - Shared pieces (copied from main.swift)

struct DurationPicker: NSViewRepresentable {
    @Binding var minutes: Int
    var glass = false

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: durations.map { $0.1 }, trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.segmentDistribution = .fillProportionally
        control.setImage(NSImage(systemSymbolName: "infinity", accessibilityDescription: "Tills vidare"), forSegment: 0)
        if glass {
            control.controlSize = .large
            control.borderShape = .capsule
            control.role = .valueSelection
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = durations.firstIndex { $0.0 == minutes } ?? -1
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? control.fittingSize.width, height: control.fittingSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: DurationPicker
        init(_ parent: DurationPicker) { self.parent = parent }
        @objc func select(_ control: NSSegmentedControl) { parent.minutes = durations[control.selectedSegment].0 }
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

let panelRadius: CGFloat = 16
let gutter: CGFloat = 14

struct MenuButton: View {
    let title: String
    @State private var isHovered = CommandLine.arguments.contains("--hover")
    private let inset: CGFloat = 6

    var body: some View {
        Button {} label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.horizontal, gutter - inset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: panelRadius - inset, style: .continuous))
        .onHover { isHovered = $0 }
        .padding(inset)
    }
}

struct MenuDivider: View {
    var body: some View { Divider().padding(.horizontal, 14).padding(.vertical, 5) }
}

struct Settings: View {
    @ObservedObject var k: FakeKoffein
    var body: some View {
        SettingRow(title: "Öppna vid inloggning", isOn: $k.opensAtLogin)
        SettingRow(title: "Aktivera vid start", isOn: $k.activatesAtLaunch)
        SettingRow(title: "Låt skärmen gå i vila", isOn: $k.allowsDisplaySleep)
    }
}

// MARK: - Nu: the menu as it ships

struct RiffNow: View {
    @ObservedObject var k: FakeKoffein

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Koffein").font(.headline)
                    if let end = k.endText { Text(end).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                Toggle("Koffein", isOn: k.activeBinding).labelsHidden()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            MenuDivider()
            DurationPicker(minutes: $k.minutes).padding(.horizontal, 14).padding(.vertical, 4)
            MenuDivider()
            Settings(k: k)
            MenuDivider()
            MenuButton(title: "Avsluta Koffein")
        }
        .padding(.top, 6)
        .frame(width: 320)
        .toggleStyle(.switch)
    }
}

// MARK: - A: same layout, Tahoe-sized native control

struct RiffTahoe: View {
    @ObservedObject var k: FakeKoffein

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Koffein").font(.headline)
                    if let end = k.endText { Text(end).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                Toggle("Koffein", isOn: k.activeBinding).labelsHidden()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            DurationPicker(minutes: $k.minutes, glass: true)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            MenuDivider()
            Settings(k: k)
            MenuDivider()
            MenuButton(title: "Avsluta Koffein")
        }
        .padding(.top, 6)
        .frame(width: 320)
        .toggleStyle(.switch)
    }
}

// MARK: - B: Control Center vocabulary

struct RiffControlCenter: View {
    @ObservedObject var k: FakeKoffein
    @Namespace private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { withAnimation(.spring(duration: 0.3, bounce: 0)) { k.toggle() } } label: {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(k.isActive ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(k.isActive ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Koffein").font(.headline)
                    Text(k.isActive ? (k.endText ?? "Tills vidare") : "Av").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Only the selection is glass (glass on glass muddies), and one shared ID lets it morph between chips.
            GlassEffectContainer {
                HStack(spacing: 4) {
                    ForEach(durations, id: \.0) { minutes, label in
                        let selected = minutes == k.minutes
                        Button { withAnimation(.spring(duration: 0.35, bounce: 0)) { k.minutes = minutes } } label: {
                            Group {
                                if minutes == 0 { Image(systemName: "infinity").font(.system(size: 12, weight: .semibold)) } else { Text(label) }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .fixedSize()
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Capsule())
                            .background(selected ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary), in: Capsule())
                            .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .identity, in: .capsule)
                            .glassEffectID(minutes, in: glass)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, gutter)

            MenuDivider().padding(.top, 6)
            IconRow(icon: "power", color: .gray, title: "Öppna vid inloggning", isOn: $k.opensAtLogin)
            IconRow(icon: "bolt.fill", color: .orange, title: "Aktivera vid start", isOn: $k.activatesAtLaunch)
            IconRow(icon: "moon.fill", color: .indigo, title: "Låt skärmen gå i vila", isOn: $k.allowsDisplaySleep)
            MenuDivider()
            MenuButton(title: "Avsluta Koffein")
        }
        .padding(.top, 6)
        .frame(width: 320)
        .toggleStyle(.switch)
    }
}

struct IconRow: View {
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
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, gutter)
        .frame(minHeight: 32)
    }
}

// MARK: - C: the remaining time is the hero, a native slider sets it

struct RiffCountdown: View {
    @ObservedObject var k: FakeKoffein
    private let steps = [15, 30, 60, 240, 480, 0]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(hero(at: context.date))
                            .font(.system(size: 40, weight: .semibold).monospacedDigit())
                            .foregroundStyle(k.isActive ? .primary : .tertiary)
                    }
                    Text(k.isActive ? (k.endText ?? "Tills vidare") : "Av")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Koffein", isOn: k.activeBinding).labelsHidden().padding(.top, 10)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)

            TickSlider(index: Binding(get: { steps.firstIndex(of: k.minutes) ?? 0 }, set: { k.minutes = steps[$0] }), count: steps.count)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            MenuDivider()
            Settings(k: k)
            MenuDivider()
            MenuButton(title: "Avsluta Koffein")
        }
        .padding(.top, 6)
        .frame(width: 320)
        .toggleStyle(.switch)
    }

    private func hero(at now: Date) -> String {
        guard k.minutes > 0 else { return "∞" }
        let minutes = k.isActive ? Int((k.endDate?.timeIntervalSince(now) ?? 0) / 60) + 1 : k.minutes
        let clamped = min(minutes, k.minutes)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }
}

struct TickSlider: NSViewRepresentable {
    @Binding var index: Int
    let count: Int

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(index), minValue: 0, maxValue: Double(count - 1), target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.integerValue = index
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView slider: NSSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: slider.fittingSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: TickSlider
        init(_ parent: TickSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) { parent.index = slider.integerValue }
    }
}

// MARK: - D: a grouped Form, the System Settings look

struct RiffForm: View {
    @ObservedObject var k: FakeKoffein

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Toggle(isOn: k.activeBinding) {
                        Text("Koffein")
                        if let end = k.endText { Text(end) }
                    }
                    Picker("Längd", selection: $k.minutes) {
                        Text("Tills vidare").tag(0)
                        Text("15 minuter").tag(15)
                        Text("30 minuter").tag(30)
                        Text("1 timme").tag(60)
                        Text("4 timmar").tag(240)
                        Text("8 timmar").tag(480)
                    }
                }
                Section {
                    Toggle("Öppna vid inloggning", isOn: $k.opensAtLogin)
                    Toggle("Aktivera vid start", isOn: $k.activatesAtLaunch)
                    Toggle("Låt skärmen gå i vila", isOn: $k.allowsDisplaySleep)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .contentMargins(.vertical, 8, for: .scrollContent)
            .frame(height: 256)
            MenuButton(title: "Avsluta Koffein")
        }
        .frame(width: 320)
        .toggleStyle(.switch)
    }
}

// MARK: - Gallery

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

@MainActor final class Gallery: NSObject, NSApplicationDelegate {
    let riffs: [(String, String, AnyView)] = [
        ("nu", "Nu", AnyView(RiffNow(k: FakeKoffein(minutes: 60)))),
        ("a-tahoe", "A · Tahoe", AnyView(RiffTahoe(k: FakeKoffein(minutes: 60)))),
        ("b-kontrollcenter", "B · Kontrollcenter", AnyView(RiffControlCenter(k: FakeKoffein(minutes: 60)))),
        ("c-nedrakning", "C · Nedräkning", AnyView(RiffCountdown(k: FakeKoffein(minutes: 60)))),
        ("d-formular", "D · Formulär", AnyView(RiffForm(k: FakeKoffein(minutes: 60)))),
    ]
    var windows: [NSWindow] = []
    let captureDir = CommandLine.arguments.firstIndex(of: "--capture").map { CommandLine.arguments[$0 + 1] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        item.submenu = NSMenu(); item.submenu!.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu

        let screen = NSScreen.main!.visibleFrame
        let width: CGFloat = 320, gap: CGFloat = 28, margin: CGFloat = 36, labelHeight: CGFloat = 34
        let hosts = riffs.map { NSHostingView(rootView: $0.2) }
        let panelHeight = hosts.map(\.fittingSize.height).max()!
        let total = NSSize(width: CGFloat(riffs.count) * width + CGFloat(riffs.count - 1) * gap + margin * 2, height: panelHeight + labelHeight + margin * 2)
        let frame = NSRect(x: screen.midX - total.width / 2, y: screen.maxY - total.height - 20, width: total.width, height: total.height)

        let backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let wallpaper = NSImageView(image: NSImage(contentsOfFile: "/System/Library/Desktop Pictures/iMac Silver.heic")!)
        wallpaper.imageScaling = .scaleAxesIndependently
        let labels = NSView()
        labels.addSubview(wallpaper)
        wallpaper.frame = NSRect(origin: .zero, size: total)
        backdrop.contentView = labels

        let window = KeyWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        let content = NSView(frame: NSRect(origin: .zero, size: total))
        window.contentView = content

        var panelRects: [NSRect] = []
        for (index, host) in hosts.enumerated() {
            let size = host.fittingSize
            let x = margin + CGFloat(index) * (width + gap)
            let rect = NSRect(x: x, y: total.height - margin - labelHeight - size.height, width: width, height: size.height)
            panelRects.append(rect)
            let shadow = NSView(frame: rect)
            shadow.wantsLayer = true
            shadow.layer!.shadowColor = NSColor.black.cgColor
            shadow.layer!.shadowOpacity = 0.22
            shadow.layer!.shadowRadius = 20
            shadow.layer!.shadowOffset = CGSize(width: 0, height: -8)
            shadow.layer!.shadowPath = CGPath(roundedRect: shadow.bounds, cornerWidth: panelRadius, cornerHeight: panelRadius, transform: nil)
            content.addSubview(shadow)
            let glass = NSGlassEffectView(frame: rect)
            glass.cornerRadius = panelRadius
            glass.contentView = host
            content.addSubview(glass)

            let label = NSTextField(labelWithString: riffs[index].1)
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .white
            label.sizeToFit()
            label.frame.origin = NSPoint(x: x + 4, y: total.height - margin - label.frame.height - 4)
            labels.addSubview(label)
        }

        backdrop.orderFront(nil)
        window.makeKeyAndOrderFront(nil)
        windows = [backdrop, window]
        NSApp.activate()

        guard let captureDir else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            let capture = unsafeBitCast(dlsym(dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW), "CGWindowListCreateImage"), to: CaptureFn.self)
            let screenHeight = NSScreen.screens[0].frame.height
            let rect = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
            guard let image = capture(rect, (1 << 2) | (1 << 3), UInt32(window.windowNumber), 1 << 3)?.takeRetainedValue() else { exit(1) }
            let scale = CGFloat(image.width) / frame.width
            write(image, to: "\(captureDir)/gallery.png")
            for (index, panel) in panelRects.enumerated() {
                let crop = CGRect(x: (panel.minX - 16) * scale, y: (total.height - panel.maxY - 16) * scale, width: (panel.width + 32) * scale, height: (panel.height + 32) * scale)
                if let cropped = image.cropping(to: crop) { write(cropped, to: "\(captureDir)/\(riffs[index].0).png") }
            }
            print("key:", window.isKeyWindow, "scale:", scale)
            exit(0)
        }
    }

    private func write(_ image: CGImage, to path: String) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

@main struct RiffsMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { Gallery() }
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
