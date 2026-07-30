import SwiftUI

struct LocationFieldRow: View {
    let icon: String
    let iconColor: Color
    let placeholder: String
    let displayText: String?
    let isActive: Bool
    @Binding var searchText: String
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            if isActive {
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .submitLabel(.search)
                    .accessibilityLabel("\(placeholder) search field")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            } else {
                Button {
                    onTap()
                } label: {
                    HStack {
                        Text(displayText ?? placeholder)
                            .font(.body)
                            .foregroundColor(displayText != nil ? .primary : .secondary)
                            .lineLimit(1)

                        Spacer()

                        if displayText != nil {
                            Button {
                                onClear()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Clear location")
                        }
                    }
                }
                .accessibilityLabel(displayText ?? placeholder)
                .accessibilityHint("Tap to search for a location")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color(.systemBackground) : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 16) {
        LocationFieldRow(
            icon: "circle.fill",
            iconColor: .green,
            placeholder: "Current Location",
            displayText: nil,
            isActive: false,
            searchText: .constant(""),
            onTap: {},
            onClear: {}
        )

        LocationFieldRow(
            icon: "mappin.circle.fill",
            iconColor: .red,
            placeholder: "Where to?",
            displayText: "Boston Common",
            isActive: false,
            searchText: .constant(""),
            onTap: {},
            onClear: {}
        )

        LocationFieldRow(
            icon: "mappin.circle.fill",
            iconColor: .red,
            placeholder: "Where to?",
            displayText: nil,
            isActive: true,
            searchText: .constant("Star"),
            onTap: {},
            onClear: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
