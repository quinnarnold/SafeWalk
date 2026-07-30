import SwiftUI
import MessageUI

struct ShareMyWalkSheet: View {
    let watchUrl: String
    let onDismiss: () -> Void
    @ObservedObject var contactStore = TrustedContactStore.shared
    @State private var showingShareSheet = false
    @State private var selectedContact: TrustedContact?

    var body: some View {
        NavigationStack {
            List {
                if !contactStore.contacts.isEmpty, MFMessageComposeViewController.canSendText() {
                    Section(header: Text("Quick Share via SMS")) {
                        ForEach(contactStore.contacts) { contact in
                            Button {
                                selectedContact = contact
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(contact.name).foregroundColor(.primary)
                                        Text(contact.phoneNumber)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "message.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack {
                            Text("Share with other...")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        TrustedContactsSettingsView()
                    } label: {
                        HStack {
                            Text("Manage Trusted Contacts")
                            Spacer()
                            Image(systemName: "person.2")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Share My Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ActivityViewController(activityItems: [URL(string: watchUrl)!])
            }
            .sheet(item: $selectedContact) { contact in
                MessageComposeView(
                    recipients: [contact.phoneNumber],
                    body: "Track my walk: \(watchUrl)"
                ) { _ in
                    onDismiss()
                }
            }
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let completion: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let completion: (MessageComposeResult) -> Void
        init(completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
            completion(result)
        }
    }
}
