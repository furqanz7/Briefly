import WidgetKit
import SwiftUI

@main
struct BrieflyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BrieflyNewsWidget()
        BrieflyMarketWidget()
        BrieflyCryptoWidget()
        BrieflySportsWidget()
        BrieflyJobsWidget()
        BrieflyBooksWidget()
    }
}
