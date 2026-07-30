import SwiftUI
import MapboxMaps
import MapboxNavigationUIKit
import MapboxNavigationCore
import Foundation

@main
struct SafeWalkApp: App {
    @StateObject private var appLoader = AppLoader()

    init() {
        Bundle.main.setTemporaryMapboxToken("loading_token")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch appLoader.state {
                case .loading:
                    LoadingLockView()
                        .task {
                            await appLoader.load()
                        }
                case .failed(let error):
                    VStack(spacing: 12) {
                        Text("Failed to initialize Mapbox")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await appLoader.load() }
                        }
                    }
                    .padding()
                case .ready:
                    ContentView()
                }
            }
        }
    }
}




extension Bundle {
    func setTemporaryMapboxToken(_ token: String) {
        guard let infoDict = Bundle.main.infoDictionary else { return }
        var mutableInfo = infoDict
        mutableInfo["MBXAccessToken"] = token
        object_setClass(Bundle.main, MutableBundle.self)
        (Bundle.main as? MutableBundle)?.overrideInfoDictionary = mutableInfo
        #if DEBUG
        print("Injected temporary Mapbox token into Info.plist memory view.")
        #endif
    }
}

private class MutableBundle: Bundle {
    var overrideInfoDictionary: [String: Any]?
    override var infoDictionary: [String: Any]? {
        overrideInfoDictionary ?? super.infoDictionary
    }
}

struct LoadingLockView: View {
    @State private var shackleOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .frame(width: 60, height: 50)
                    .offset(y: 15)

                LockShackle()
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 40, height: 35)
                    .offset(y: shackleOffset)

                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .offset(y: 12)
            }
            .frame(width: 80, height: 100)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                ) {
                    shackleOffset = -10
                }
            }

            Text("Securing connection…")
                .font(.headline)
                .foregroundColor(.secondary)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
        }
    }
}

struct LockShackle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: 0, y: height))

        path.addLine(to: CGPoint(x: 0, y: height * 0.4))

        path.addArc(
            center: CGPoint(x: width / 2, y: height * 0.4),
            radius: width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: width, y: height))

        return path
    }
}
