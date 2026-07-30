import SwiftUI

struct CurrentLocationRow: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                    )

                Text("Current Location")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current Location")
        .accessibilityHint("Use your current location as the starting point")
    }
}

#Preview {
    VStack {
        CurrentLocationRow(onTap: {})
        Divider()
    }
    .background(Color(.systemBackground))
}
