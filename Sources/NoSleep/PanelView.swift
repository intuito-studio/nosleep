import AppKit
import NoSleepCore
import SwiftUI

/// Laid out like a Control Center module, and built from the system's own
/// pieces: Liquid Glass tiles, native sliders, a glass button. Nothing here
/// draws its own control.
struct PanelView: View {
    let controller: Controller

    var body: some View {
        GlassGroup {
            VStack(spacing: 10) {
                AwakeTile(controller: controller)

                if let problem = controller.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }

                VStack(spacing: 14) {
                    StopSlider(
                        title: "Keep awake for",
                        value: Format.durationName(controller.duration),
                        systemImage: "timer",
                        choices: Controller.durationChoices,
                        selection: Binding(get: { controller.duration }, set: { controller.setDuration($0) })
                    )
                    if let percent = controller.power.batteryPercent {
                        StopSlider(
                            title: "Stop at battery",
                            value: controller.batteryFloor.map { "\($0)%" } ?? "Off",
                            detail: "now \(percent)%" + (controller.power.onBattery ? "" : ", charging"),
                            systemImage: "battery.25percent",
                            choices: Controller.batteryFloorChoices,
                            selection: Binding(get: { controller.batteryFloor }, set: { controller.batteryFloor = $0 })
                        )
                    }
                }
                .padding(14)
                .glassTile()

                if controller.hasPasswordFreeAccess, !controller.ruleIsCurrent {
                    AccessUpdateRow(controller: controller)
                }

                HotspotRow(controller: controller)

                if !controller.log.isEmpty {
                    ActivityLog(events: controller.log)
                }

                footer
                    .padding(.leading, 8)
            }
        }
        .padding(10)
        .frame(width: 300)
        .panelSheet()
    }

    private var footer: some View {
        HStack {
            Toggle(
                "Open at login",
                isOn: Binding(get: { controller.launchesAtLogin }, set: { controller.setLaunchesAtLogin($0) })
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Palette.amber)
            .font(.system(size: 12))

            Spacer()

            Button("Quit") { controller.quit() }
                .glassButton()
                .keyboardShortcut("q")
        }
    }
}

// MARK: - The switch

private struct AwakeTile: View {
    let controller: Controller

    var body: some View {
        Button { controller.setAwake(!controller.isAwake) } label: {
            HStack(spacing: 12) {
                StateCircle(isAwake: controller.isAwake, fractionLeft: controller.timerFractionLeft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.isAwake ? "Awake" : "Normal sleep")
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: GlassTile.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassTile(interactive: true)
        .accessibilityLabel("Keep awake")
        .accessibilityValue(controller.isAwake ? "On, \(subtitle)" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var subtitle: String {
        if controller.isAwake {
            guard let until = controller.until else { return "Lid closed keeps it running" }
            let left = Format.remaining(until.timeIntervalSince(controller.now))
            return "\(left) left · until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if let stop = controller.lastStop {
            let at = stop.at.formatted(date: .omitted, time: .shortened)
            switch stop.reason {
            case .timer: return "Timer ended at \(at)"
            case .battery(let percent): return "Stopped at \(at), battery \(percent)%"
            case .heat: return "Stopped at \(at), the Mac got too hot"
            }
        }
        if !controller.hasPasswordFreeAccess {
            return "Click to stay awake. Asks for your password once."
        }
        return "Sleeps when the lid closes"
    }
}

/// Control Center's round toggle: filled with the tint when on, a quiet disc when off.
private struct StateCircle: View {
    let isAwake: Bool
    let fractionLeft: Double?

    var body: some View {
        ZStack {
            Circle().fill(isAwake ? AnyShapeStyle(Palette.amber) : AnyShapeStyle(.fill.secondary))
            if isAwake {
                Image(nsImage: CatGlyph.awake.badgeImage(points: 20))
            } else {
                Image(nsImage: CatGlyph.asleep.badgeImage(points: 20))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 38, height: 38)
        .overlay {
            // How much of the timer is left, draining clockwise like a clock face.
            if let fractionLeft {
                ZStack {
                    Circle().stroke(Palette.amber.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fractionLeft)
                        .stroke(Palette.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(-5)
            }
        }
        .padding(5)
        .animation(.snappy, value: isAwake)
    }
}

// MARK: - Below the sliders

private struct AccessUpdateRow: View {
    let controller: Controller

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("Low Power Mode needs your password once more.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Allow") { controller.updateAccess() }
                .glassButton()
        }
        .padding(12)
        .glassTile()
    }
}

/// Off until it is given a hotspot name. The password is optional: a hotspot
/// this Mac has joined before is already in the system's keychain.
private struct HotspotRow: View {
    let controller: Controller
    @State private var editing = false
    @State private var name = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "personalhotspot")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(controller.hotspotName == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.amber))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("iPhone hotspot")
                        .font(.system(size: 13, weight: .semibold))
                    Text(controller.hotspotName.map { "Joins \($0) if the Wi-Fi drops" } ?? "Off until set up")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !editing {
                    Button(controller.hotspotName == nil ? "Set up" : "Edit") {
                        name = controller.hotspotName ?? ""
                        password = ""
                        editing = true
                    }
                    .glassButton()
                }
            }

            if editing {
                TextField("Hotspot name, as on the iPhone", text: $name)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password (optional if joined before)", text: $password)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if controller.hotspotName != nil {
                        Button("Remove", role: .destructive) {
                            controller.removeHotspot()
                            editing = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Cancel") { editing = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("Save") {
                        controller.saveHotspot(name: name, password: password)
                        editing = false
                    }
                    .glassButton()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .font(.system(size: 12))
            }
        }
        .padding(12)
        .glassTile()
    }
}

/// The last few things a session did, newest first, like a log read back in the morning.
private struct ActivityLog: View {
    let events: [SessionEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.system(size: 13, weight: .semibold))
            ForEach(events.suffix(5).reversed()) { event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(event.at.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 12, weight: .medium))
                        if !event.detail.isEmpty {
                            Text(event.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassTile()
    }
}

// MARK: - Sliders

/// A native slider over a fixed set of stops. It moves in whole steps, and
/// the step is what gets stored, not a position.
private struct StopSlider<Value: Hashable>: View {
    let title: String
    let value: String
    var detail: String?
    let systemImage: String
    let choices: [Value]
    @Binding var selection: Value

    init(
        title: String, value: String, detail: String? = nil, systemImage: String,
        choices: [Value], selection: Binding<Value>
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.choices = choices
        _selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()

            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Slider(value: index, in: 0...Double(choices.count - 1), step: 1) { Text(title) }
                    .labelsHidden()
            }
            .accessibilityValue(value)
        }
    }

    private var index: Binding<Double> {
        Binding(
            get: { Double(choices.firstIndex(of: selection) ?? 0) },
            set: { selection = choices[min(max(Int($0.rounded()), 0), choices.count - 1)] }
        )
    }
}

// MARK: - Glass

private enum GlassTile {
    static let radius: CGFloat = 18
    /// The panel's gap around the tiles is 10, so the sheet's corners share
    /// their centre with the tiles' corners.
    static let sheetRadius: CGFloat = radius + 10
}

private extension View {
    /// A Liquid Glass tile on macOS 26 and later; a plain platter before that.
    @ViewBuilder
    func glassTile(interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassTile.radius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.fill.quaternary, in: shape)
        }
    }

    /// The outer sheet the tiles sit on, drawn here because the system's own
    /// corner is too tight for them (see `StatusPanel`).
    @ViewBuilder
    func panelSheet() -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassTile.sheetRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// Lets neighbouring glass tiles share one sampling pass and blend at their
/// edges, the way Control Center's modules do.
private struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 10) { content }
        } else {
            content
        }
    }
}

enum Palette {
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.10)
}

enum Format {
    /// "15 minutes", "1 hour", "No limit".
    static func durationName(_ interval: TimeInterval?) -> String {
        guard let interval else { return "No limit" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) minutes" }
        return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }

    /// "1h 42m", "42m", "<1m". Rounded up, so it never reads 0m while still running.
    static func remaining(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return "<1m" }
        let minutes = Int((interval / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// For the menu bar, where width is scarce: "1:42", "42m".
    static func compact(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return "<1m" }
        let minutes = Int((interval / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
