import Testing
import CoreGraphics
@testable import CoachCore

let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]

@Test func windowGoesToScreenWithMostOverlap() {
    #expect(screenIndex(forWindowBounds: CGRect(x: 100, y: 100, width: 800, height: 600), screenFrames: screens) == 0)
    #expect(screenIndex(forWindowBounds: CGRect(x: 2000, y: 100, width: 800, height: 600), screenFrames: screens) == 1)
    #expect(screenIndex(forWindowBounds: CGRect(x: 1400, y: 100, width: 800, height: 600), screenFrames: screens) == 1)
}
@Test func windowOnNoScreenGivesNil() {
    #expect(screenIndex(forWindowBounds: CGRect(x: 9000, y: 9000, width: 10, height: 10), screenFrames: screens) == nil)
    #expect(screenIndex(forWindowBounds: CGRect(x: 0, y: 0, width: 10, height: 10), screenFrames: []) == nil)
}
@Test func badgeSitsAtCentreOfFrontmostWindowPerApp() {
    let w = [WindowInfo(pid: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
             WindowInfo(pid: 1, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
             WindowInfo(pid: 2, bounds: CGRect(x: 200, y: 0, width: 100, height: 100))]
    #expect(badgePoints(windows: w, pids: [1, 2]) == [1: CGPoint(x: 50, y: 50), 2: CGPoint(x: 250, y: 50)])
}
@Test func coveredCentreAndUnlistedAppsGetNoBadge() {
    let w = [WindowInfo(pid: 9, bounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
             WindowInfo(pid: 1, bounds: CGRect(x: 100, y: 100, width: 100, height: 100))]
    #expect(badgePoints(windows: w, pids: [1, 3]).isEmpty)
}
