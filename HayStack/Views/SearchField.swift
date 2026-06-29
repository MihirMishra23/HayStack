import SwiftUI

struct SearchField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("Search files...", text: $text)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isFocused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
