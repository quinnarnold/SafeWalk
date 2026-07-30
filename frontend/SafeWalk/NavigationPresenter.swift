import UIKit
import CoreLocation
import MapboxNavigationUIKit
import MapboxNavigationCore
import MapboxMaps
import ActivityKit
import MapboxDirections

final class NavigationPresenter: NSObject {

    static let shared = NavigationPresenter()
    static let navigationProvider = MapboxNavigationProvider(coreConfig: .init())

    private var liveActivity: Activity<SafeWalkNavigationAttributes>?
    private var lastUpdateTime: Date = .distantPast
    private var lastStepIndex: Int = -1
    private var totalDistance: Double = 0
    private var shareSessionId: String?
    private var shareWriterToken: String?
    private var shareCity: String?
    private var lastShareUpdateTime: Date = .distantPast
    private var dismissCallback: (@MainActor (Bool) -> Void)?

    private override init() {
        super.init()
    }

    func present(navRoutes: NavigationRoutes,
                 startCoordinate: CLLocationCoordinate2D?,
                 destinationName: String = "Destination",
                 routeType: String = "moderate",
                 totalDistance: Double = 0,
                 onDismiss: (@MainActor (Bool) -> Void)? = nil) {

        guard let top = Self.topMostViewController() else {
            print("NavigationPresenter: no view controller to present from.")
            return
        }

        self.totalDistance = totalDistance
        self.dismissCallback = onDismiss

        let options = NavigationOptions(
            mapboxNavigation: Self.navigationProvider.mapboxNavigation,
            voiceController: Self.navigationProvider.routeVoiceController,
            eventsManager: Self.navigationProvider.eventsManager(),
            styles: [StandardDayStyle(), StandardNightStyle()]
        )
        let navVC = NavigationViewController(navigationRoutes: navRoutes, navigationOptions: options)
        navVC.modalPresentationStyle = .fullScreen
        navVC.automaticallyAdjustsStyleForTimeOfDay = false
        navVC.usesNightStyleInDarkMode = true
        navVC.delegate = self

        top.present(navVC, animated: true) { [weak self] in
            navVC.navigationMapView?.navigationCamera.update(cameraState: .overview)
            self?.startLiveActivity(
                destinationName: destinationName,
                routeType: routeType,
                totalDistance: totalDistance
            )
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(destinationName: String, routeType: String, totalDistance: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = SafeWalkNavigationAttributes(
            destinationName: destinationName,
            routeType: routeType,
            totalDistanceMeters: totalDistance
        )

        let walkingSpeed = 1.4 // meters per second
        let initialState = SafeWalkNavigationAttributes.ContentState(
            currentStepName: "Starting navigation",
            nextManeuverIcon: "figure.walk",
            distanceToNextManeuverMeters: 0,
            distanceRemainingMeters: totalDistance,
            estimatedArrival: Date().addingTimeInterval(totalDistance / walkingSpeed),
            fractionComplete: 0
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            liveActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            // ActivityKit unavailable or denied
        }
    }

    private func updateLiveActivity(
        stepName: String,
        maneuverType: String,
        maneuverModifier: String?,
        distanceToManeuver: Double,
        distanceRemaining: Double,
        durationRemaining: Double,
        stepIndex: Int
    ) {
        guard liveActivity != nil else { return }

        let now = Date()
        let stepChanged = stepIndex != lastStepIndex
        let timeSinceUpdate = now.timeIntervalSince(lastUpdateTime)
        let approachingTurn = distanceToManeuver < 50

        guard stepChanged || timeSinceUpdate >= 5 || approachingTurn else { return }

        lastUpdateTime = now
        lastStepIndex = stepIndex

        let fractionComplete = totalDistance > 0
            ? max(0, min(1, 1.0 - (distanceRemaining / totalDistance)))
            : 0

        let state = SafeWalkNavigationAttributes.ContentState(
            currentStepName: stepName,
            nextManeuverIcon: ManeuverIcon.sfSymbol(for: maneuverType, modifier: maneuverModifier),
            distanceToNextManeuverMeters: distanceToManeuver,
            distanceRemainingMeters: distanceRemaining,
            estimatedArrival: Date().addingTimeInterval(durationRemaining),
            fractionComplete: fractionComplete
        )

        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await liveActivity?.update(content)
        }
    }

    private func endLiveActivity(canceled: Bool = false) {
        guard let liveActivity else { return }

        if canceled {
            Task {
                await liveActivity.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            let finalState = SafeWalkNavigationAttributes.ContentState(
                currentStepName: "Arrived",
                nextManeuverIcon: "flag.checkered.2.crossed",
                distanceToNextManeuverMeters: 0,
                distanceRemainingMeters: 0,
                estimatedArrival: .now,
                fractionComplete: 1.0
            )

            Task {
                let content = ActivityContent(state: finalState, staleDate: nil)
                await liveActivity.end(content, dismissalPolicy: .after(.now + 30))
            }
        }

        self.liveActivity = nil
        self.lastStepIndex = -1
        self.lastUpdateTime = .distantPast

        if let sessionId = shareSessionId, let writerToken = shareWriterToken, let city = shareCity {
            Task {
                try? await ApiService.shared.stopShareSession(
                    city: city,
                    sessionId: sessionId,
                    writerToken: writerToken,
                    reason: canceled ? "canceled" : "arrived"
                )
            }
            self.shareSessionId = nil
            self.shareWriterToken = nil
            self.shareCity = nil
            self.lastShareUpdateTime = .distantPast
        }
    }

    // MARK: - Share My Walk

    func setShareSession(sessionId: String, writerToken: String, city: String) {
        self.shareSessionId = sessionId
        self.shareWriterToken = writerToken
        self.shareCity = city
    }

    // MARK: - Utilities

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? (scenes.first as? UIWindowScene)
        if let scene = windowScene {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                var top = window.rootViewController
                while let presented = top?.presentedViewController { top = presented }
                return top
            }
        }
        return nil
    }
}

// MARK: - NavigationViewControllerDelegate

extension NavigationPresenter: NavigationViewControllerDelegate {

    func navigationViewController(
        _ navigationViewController: NavigationViewController,
        didUpdate progress: RouteProgress,
        with location: CLLocation,
        rawLocation: CLLocation
    ) {
        let step = progress.currentLegProgress.currentStep
        let stepIndex = progress.currentLegProgress.stepIndex

        updateLiveActivity(
            stepName: step.instructions,
            maneuverType: step.maneuverType.rawValue,
            maneuverModifier: step.maneuverDirection?.rawValue,
            distanceToManeuver: progress.currentLegProgress.currentStepProgress.distanceRemaining,
            distanceRemaining: progress.distanceRemaining,
            durationRemaining: progress.durationRemaining,
            stepIndex: stepIndex
        )

        if let sessionId = shareSessionId, let writerToken = shareWriterToken, let city = shareCity,
           Date().timeIntervalSince(lastShareUpdateTime) >= 5 {
            lastShareUpdateTime = Date()
            Task {
                try? await ApiService.shared.sendShareLocation(
                    city: city,
                    sessionId: sessionId,
                    writerToken: writerToken,
                    lat: location.coordinate.latitude,
                    lon: location.coordinate.longitude
                )
            }
        }
    }

    func navigationViewControllerDidDismiss(
        _ navigationViewController: NavigationViewController,
        byCanceling canceled: Bool
    ) {
        endLiveActivity(canceled: canceled)
        let callback = dismissCallback
        dismissCallback = nil
        navigationViewController.dismiss(animated: true) {
            if let callback {
                Task { @MainActor in callback(canceled) }
            }
        }
    }
}
