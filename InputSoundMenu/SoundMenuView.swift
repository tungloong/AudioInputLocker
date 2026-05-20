import SwiftUI

struct SoundMenuView: View {
    @ObservedObject var viewModel: AudioInputViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                Text("Sound")
                    .font(.headline.weight(.semibold))

                HStack {
                    Image(systemName: "mic.and.signal.meter.fill", variableValue: 0.25)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { viewModel.currentVolume },
                            set: { viewModel.setCurrentVolume($0) }
                        ),
                        in: 0...1
                    )
                    .tint(Color(nsColor: .systemBlue))
                    .controlSize(.small)
                    .disabled(!viewModel.volumeIsEnabled)

                    Image(systemName: "mic.and.signal.meter.fill", variableValue: 1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 0) {
                Text("Input")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                    .padding(.horizontal)

                if viewModel.hasDevices {
                    ForEach(viewModel.devices) { device in
                        InputDeviceRow(device: device) {
                            viewModel.select(device)
                        }
                    }
                } else {
                    Text("No Input Devices")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 8)

            InputLockSection(
                state: viewModel.inputLockSectionState,
                setIsEnabled: viewModel.setInputLockEnabled,
                toggleRow: viewModel.toggleInputLockRow
            )

            if let errorMessage = viewModel.errorMessage {
                Divider()
                    .padding(.horizontal)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Divider()
                .padding(.horizontal, 8)

            Button {
                viewModel.openSoundSettings()
            } label: {
                Text("Sound Settings...")
                    .padding(.horizontal, MenuMetrics.rowContentInset)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .menuItemHover()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MenuMetrics.rowOuterInset)
            .padding(.vertical, 4)
        }
        .frame(width: 308)
        .onAppear {
            viewModel.menuDidOpen()
        }
    }
}

private struct InputLockSection: View {
    let state: InputLockSectionState
    let setIsEnabled: (Bool) -> Void
    let toggleRow: (InputLockRowState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lock Input Device")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { state.isEnabled },
                        set: setIsEnabled
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.bottom, state.isEnabled && !state.rows.isEmpty ? 6 : 0)

            if state.isEnabled {
                ForEach(state.rows) { row in
                    InputLockRow(row: row) {
                        toggleRow(row)
                    }
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

private struct InputLockRow: View {
    let row: InputLockRowState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuMetrics.deviceTextSpacing) {
                InputLockBadge(row: row)

                Text(row.deviceName)
                    .foregroundStyle(row.isOnline ? Color.primary : Color(nsColor: .disabledControlTextColor))
                    .opacity(textOpacity)
                    .lineLimit(1)
 
                Spacer()
            }
            .padding(.horizontal, MenuMetrics.rowContentInset)
            .padding(.vertical, MenuMetrics.deviceRowVerticalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .menuItemHover()
            .opacity(row.isActionable || row.lockAnimationDeadline != nil ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!row.isActionable && row.lockAnimationDeadline == nil)
        .allowsHitTesting(row.isActionable)
        .padding(.horizontal, MenuMetrics.rowOuterInset)
    }

    private var textOpacity: Double {
        if !row.isOnline {
            return 0.72
        }

        return row.role == .released ? 0.68 : 1
    }
}

private struct InputLockBadge: View {
    let row: InputLockRowState

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)

            Image(systemName: symbolName)
                .font(.system(size: MenuMetrics.lockIconSymbolSize, weight: .semibold))
                .foregroundStyle(foregroundColor)

            progressRing
        }
        .frame(width: 26, height: 26)
        .opacity(row.isOnline ? 1 : 0.62)
    }

    @ViewBuilder
    private var progressRing: some View {
        if let deadline = activeDeadline,
           let duration = activeDuration {
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let remaining = max(deadline.timeIntervalSince(context.date), 0)
                let rawProgress = min(max(1 - remaining / duration, 0), 1)
                let progress = row.lockAnimationDeadline == nil
                    ? rawProgress
                    : min(max(rawProgress, 0.08), 1)

                ZStack {
                    Circle()
                        .stroke(Color(nsColor: .systemBrown).opacity(0.24), lineWidth: 1.1)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color(nsColor: .systemBrown),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .padding(1.4)
            }
        }
    }

    private var symbolName: String {
        row.lockAnimationDeadline == nil && row.isLocked ? "lock.fill" : "lock.open.fill"
    }

    private var backgroundColor: Color {
        if !row.isOnline {
            return Color(nsColor: .disabledControlTextColor).opacity(0.07)
        }

        if row.lockAnimationDeadline != nil || row.countdownDeadline != nil {
            return Color.deviceIconBackground
        }

        if row.isLocked {
            return Color(nsColor: .systemBrown)
        }

        return Color.deviceIconBackground
    }

    private var foregroundColor: Color {
        if !row.isOnline {
            return Color(nsColor: .disabledControlTextColor)
        }

        if row.lockAnimationDeadline != nil || row.countdownDeadline != nil {
            return .secondary
        }

        return row.isLocked ? .white : .secondary
    }

    private var activeDeadline: Date? {
        row.lockAnimationDeadline ?? row.countdownDeadline
    }

    private var activeDuration: TimeInterval? {
        row.lockAnimationDuration ?? row.countdownDuration
    }
}

private struct InputDeviceRow: View {
    let device: InputDevice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuMetrics.deviceTextSpacing) {
                ZStack {
                    Circle()
                        .fill(device.isDefault ? Color(nsColor: .systemBlue) : .deviceIconBackground)

                    Image(systemName: device.iconSystemName)
                        .font(.system(size: MenuMetrics.deviceIconSymbolSize, weight: .medium))
                        .foregroundStyle(device.isDefault ? .white : .secondary)
                }
                .frame(width: 26, height: 26)

                Text(device.displayName)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, MenuMetrics.rowContentInset)
            .padding(.vertical, MenuMetrics.deviceRowVerticalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .menuItemHover()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MenuMetrics.rowOuterInset)
        .accessibilityLabel(device.displayName)
    }
}

private struct MenuItemHover: ViewModifier {
    @State private var isHovered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background(
                Color.menuHoverBackground.opacity(isHovered ? 1 : 0),
                in: .menuSelectionBackground
            )
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func menuItemHover() -> some View {
        modifier(MenuItemHover())
    }
}

private extension Color {
    static var deviceIconBackground: Color {
        Color(nsColor: .labelColor).opacity(0.115)
    }

    static var menuHoverBackground: Color {
        Color(nsColor: .labelColor).opacity(0.11)
    }
}

private extension Shape where Self == RoundedRectangle {
    static var menuSelectionBackground: RoundedRectangle {
        .rect(cornerRadius: 8, style: .continuous)
    }
}

private enum MenuMetrics {
    static let rowOuterInset: CGFloat = 8
    static let rowContentInset: CGFloat = 8
    static let deviceTextSpacing: CGFloat = 10
    static let deviceRowVerticalInset: CGFloat = 2
    static let deviceIconSymbolSize: CGFloat = 14
    static let lockIconSymbolSize: CGFloat = 13
}
