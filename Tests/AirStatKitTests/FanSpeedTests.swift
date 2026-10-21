import Testing
@testable import AirStatKit

@Suite("A fan's speed as a percentage")
struct FanSpeedTests {

    @Test("the percentage is the speed over the top speed, counted from stopped")
    func shareOfTopSpeed() {
        #expect(FanInfo(id: 0, name: "Left", currentRPM: 1450, minRPM: 1200, maxRPM: 5800).speedFraction == 0.25)
        #expect(FanInfo(id: 0, name: "Left", currentRPM: 0, minRPM: 1200, maxRPM: 5800).speedFraction == 0)
        #expect(FanInfo(id: 0, name: "Left", currentRPM: 7000, maxRPM: 5800).speedFraction == 1)
    }

    @Test("a fan that does not report its top speed is taken to top out at 6,000 RPM")
    func assumedTopSpeed() {
        #expect(FanInfo(id: 0, name: "Left", currentRPM: 3000).speedFraction == 0.5)
        #expect(FanInfo(id: 0, name: "Left", currentRPM: 3000, maxRPM: 0).speedFraction == 0.5)
    }
}
