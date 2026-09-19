import Foundation
import Testing

@testable import SakeKit

@Test func appleSiliconIsTheOnlySupportedMachine() {
    #expect(Requirement.appleSilicon(isARM64: true).status.isSatisfied)
    #expect(!Requirement.appleSilicon(isARM64: false).status.isSatisfied)
}

@Test func rosettaIsReportedWithoutOfferingToInstallIt() {
    #expect(Requirement.rosetta(isInstalled: true).status.isSatisfied)

    guard case .actionNeeded(_, let remedy) = Requirement.rosetta(isInstalled: false).status else {
        Issue.record("a missing Rosetta has to be actionable")
        return
    }
    #expect(remedy.contains("softwareupdate --install-rosetta"))
}

@Test func commandLineToolsNeedAUsableClang() {
    let found = Requirement.commandLineTools(clangPath: "/usr/bin/clang")
    #expect(found.status == .satisfied("clang at /usr/bin/clang"))

    #expect(!Requirement.commandLineTools(clangPath: nil).status.isSatisfied)
    #expect(!Requirement.commandLineTools(clangPath: "").status.isSatisfied)
}

@Test func anInstalledD3DMetalSettlesTheToolkitCheck() {
    let requirement = Requirement.gamePortingToolkit(
        d3dMetalInstalled: true,
        mountedVolumes: [],
        nestedImageNames: []
    )

    #expect(requirement.status == .satisfied("D3DMetal is already installed in the engine."))
}

@Test func theMountedInnerVolumeIsMatchedByPrefixBecauseItCarriesAVersion() {
    let requirement = Requirement.gamePortingToolkit(
        d3dMetalInstalled: false,
        mountedVolumes: ["Macintosh HD", "Evaluation environment for Windows games 4.0 beta 2"],
        nestedImageNames: []
    )

    #expect(requirement.status == .satisfied("Mounted: Evaluation environment for Windows games 4.0 beta 2"))
}

@Test func theNestedImageCountsBecauseSakeCanMountItItself() {
    let requirement = Requirement.gamePortingToolkit(
        d3dMetalInstalled: false,
        mountedVolumes: ["Game Porting Toolkit"],
        nestedImageNames: ["Evaluation environment for Windows games 4.0 beta 2.dmg", "metal-cpp"]
    )

    guard case .satisfied(let detail) = requirement.status else {
        Issue.record("a nested image sake can mount is not a problem for the user to solve")
        return
    }
    #expect(detail.hasPrefix("Evaluation environment for Windows games 4.0 beta 2.dmg"))
}

@Test func withoutTheToolkitTheUserIsPointedAtApple() {
    let requirement = Requirement.gamePortingToolkit(
        d3dMetalInstalled: false,
        mountedVolumes: ["Macintosh HD"],
        nestedImageNames: []
    )

    guard case .actionNeeded(let problem, let remedy) = requirement.status else {
        Issue.record("nothing mounted means the user has to act")
        return
    }
    #expect(problem.contains("may not ship"))
    #expect(remedy.contains(GamePortingToolkit.downloadPage))
    #expect(remedy.contains("free Apple ID"))
}

@Test func diskSpaceIsJudgedAgainstWhatTheBuildNeeds() {
    #expect(Requirement.diskSpace(availableBytes: Preflight.requiredCacheBytes).status.isSatisfied)
    #expect(!Requirement.diskSpace(availableBytes: Preflight.requiredCacheBytes - 1).status.isSatisfied)
    #expect(!Requirement.diskSpace(availableBytes: nil).status.isSatisfied)
}

@Test func everyRequirementIsReportedExactlyOnce() async {
    let requirements = await Preflight.run()

    #expect(requirements.map(\.kind) == Requirement.Kind.allCases)
}

@Test func nothingIsLeftWithoutSomethingToRead() async {
    for requirement in await Preflight.run() {
        #expect(!requirement.title.isEmpty)
        switch requirement.status {
        case .satisfied(let detail):
            #expect(!detail.isEmpty)
        case .actionNeeded(let problem, let remedy):
            #expect(!problem.isEmpty)
            #expect(!remedy.isEmpty, "a failure has to say what to do next")
        }
    }
}
