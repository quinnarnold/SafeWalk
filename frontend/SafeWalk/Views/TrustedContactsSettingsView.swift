import SwiftUI
import ContactsUI

struct TrustedContactsSettingsView: View {
    @ObservedObject var store = TrustedContactStore.shared
    @State private var showingPicker = false

    var body: some View {
        List {
            Section(header: Text("Trusted Contacts")) {
                ForEach(store.contacts) { contact in
                    VStack(alignment: .leading) {
                        Text(contact.name).font(.body)
                        Text(contact.phoneNumber)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onDelete(perform: store.remove)

                if store.contacts.count < 3 {
                    Button("Add from Contacts") { showingPicker = true }
                }
            }

            Section(footer: Text("These contacts will appear for quick sharing when you tap Share My Walk.")) {
                EmptyView()
            }
        }
        .navigationTitle("Share My Walk")
        .sheet(isPresented: $showingPicker) {
            ContactPicker { name, phone in
                store.add(TrustedContact(name: name, phoneNumber: phone))
            }
        }
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    let onSelect: (String, String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (String, String) -> Void

        init(onSelect: @escaping (String, String) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let phone = contact.phoneNumbers.first?.value else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Unknown"
            let raw = phone.stringValue
            let digits = raw.filter { $0.isNumber || $0 == "+" }
            onSelect(name, digits)
        }
    }
}
