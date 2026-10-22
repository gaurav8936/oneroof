import XCTest
@testable import OneRoofCore

/// LAB-516: reading launchd's view of roofd's job.
final class LaunchdJobTests: XCTestCase {
    let healthy = """
    gui/501/io.github.gaurav8936.oneroof.roofd = {
    \tactive count = 1
    \tpath = (submitted by smd.52861)
    \tstate = running
    \tprogram identifier = Contents/MacOS/roofd (mode: 2)
    \truns = 1
    \tlast exit code = (never exited)
    \tproperties = partial import | keepalive | runatload | abandon process group | resolve program | has LWCR
    }
    """
    let stuck = """
    gui/501/io.github.gaurav8936.oneroof.roofd = {
    \tstate = spawn scheduled
    \truns = 62
    \tlast exit code = 78: EX_CONFIG
    \tjob state = exited
    \tproperties = partial import | keepalive | runatload | needs LWCR update
    }
    """

    func testHealthyJob() {
        let j = LaunchdJob.parse(healthy)
        XCTAssertEqual(j?.state, "running"); XCTAssertNil(j?.lastExit); XCTAssertEqual(j?.runs, 1)
        XCTAssertEqual(j?.healthy, true); XCTAssertEqual(j?.stuck, false)
    }

    func testStuckAfterDevToReleaseSwitch() {
        let j = LaunchdJob.parse(stuck)
        XCTAssertEqual(j?.lastExit, 78); XCTAssertEqual(j?.needsLWCR, true)
        XCTAssertEqual(j?.healthy, false); XCTAssertEqual(j?.stuck, true)
    }

    func testNoJob() {
        XCTAssertNil(LaunchdJob.parse("Bad request.\nCould not find service \"io.github.gaurav8936.oneroof.roofd\" in domain for user gui: 501\n"))
        XCTAssertNil(LaunchdJob.parse(""))
    }
}
