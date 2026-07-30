import WidgetKit
import SwiftUI

@main
struct SafeWalkWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickRouteWidget()
        LockScreenWidget()
        SafeWalkLiveActivityView()
    }
}
