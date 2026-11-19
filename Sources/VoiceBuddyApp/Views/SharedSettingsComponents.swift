import AppKit
import SwiftUI

struct SettingRow<Control: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let control: () -> Control

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 3)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 8) {
                content()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct StatusModuleButton: View {
    let number: Int
    let title: String
    let subtitle: String
    let isReady: Bool
    let isPreparing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .foregroundStyle(isReady ? Color.green : (isPreparing ? Color.blue : Color.orange))
                        .frame(width: 18, height: 18)
                        .background((isReady ? Color.green : (isPreparing ? Color.blue : Color.orange)).opacity(0.15))
                        .clipShape(Circle())

                    Spacer()

                    if isPreparing {
                        ProgressView().controlSize(.small)
                    } else if isReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                    }
                }

                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isReady ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isReady ? Color.green.opacity(0.25) : (isPreparing ? Color.blue.opacity(0.3) : Color.orange.opacity(0.35)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(title): \(subtitle)")
    }
}

struct AuthorizedStatusBadge: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

struct CollapsibleContextPreview: View {
    let title: String
    let headerCaption: String
    let copyButtonTitle: String
    let copiedTitle: String
    let content: String
    @Binding var isExpanded: Bool
    @Binding var copiedTip: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(headerCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                            copiedTip = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedTip = false
                            }
                        } label: {
                            Label(
                                copiedTip ? copiedTitle : copyButtonTitle,
                                systemImage: copiedTip ? "checkmark" : "doc.on.doc"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    ScrollView {
                        Text(content)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(height: 140)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .padding(.top, 8)
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
    }
}
