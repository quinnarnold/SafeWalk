import SwiftUI
import Combine

struct TrustedContact: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var phoneNumber: String
}

final class TrustedContactStore: ObservableObject {
    static let shared = TrustedContactStore()

    private let key = "com.safewalk.trustedContacts"

    @Published var contacts: [TrustedContact] = [] {
        didSet { save() }
    }

    private init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TrustedContact].self, from: data)
        else { return }
        contacts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ contact: TrustedContact) {
        guard contacts.count < 3 else { return }
        contacts.append(contact)
    }

    func remove(at offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
    }
}
