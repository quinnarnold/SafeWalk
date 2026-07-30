import SwiftUI
import CoreLocation

struct SaveRouteSheet: View {
    @ObservedObject var viewModel: RouteViewModel
    let routeToSave: RouteInfo?
    @Binding var isPresented: Bool

    @State private var routeName = ""
    @State private var selectedType: FavoriteRouteType = .custom
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Route name", text: $routeName)
                        .focused($isNameFocused)
                } header: {
                    Text("Name")
                } footer: {
                    Text("e.g., Morning Commute, Grocery Run")
                }

                Section("Quick Assign") {
                    Button {
                        selectedType = .home
                        if routeName.isEmpty { routeName = "Home to Work" }
                    } label: {
                        HStack {
                            Label("Set as Home \u{2192} Work", systemImage: "house.fill")
                            Spacer()
                            if selectedType == .home {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        selectedType = .work
                        if routeName.isEmpty { routeName = "Work to Home" }
                    } label: {
                        HStack {
                            Label("Set as Work \u{2192} Home", systemImage: "briefcase.fill")
                            Spacer()
                            if selectedType == .work {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }

                if selectedType != .custom {
                    Section {
                        Button("Save as custom instead") {
                            selectedType = .custom
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRoute()
                    }
                    .disabled(routeName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func saveRoute() {
        guard let route = routeToSave,
              let source = viewModel.sourceCoord,
              let dest = viewModel.destCoord,
              let geometry = viewModel.routeGeometry else {
            return
        }

        viewModel.saveFavoriteRoute(
            name: routeName.trimmingCharacters(in: .whitespaces),
            source: source,
            destination: dest,
            routeType: route.type,
            geometry: geometry,
            distance: route.distance,
            time: route.time,
            favoriteType: selectedType
        )

        isPresented = false
    }
}
