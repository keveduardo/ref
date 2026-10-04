import Foundation
import Testing
@testable import RefKit

@Suite("team library")
struct TeamLibraryTests {
    func tempLibrary() -> TeamLibrary {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("refkit-lib-\(UUID().uuidString)", isDirectory: true)
        return TeamLibrary(directory: dir)
    }

    @Test func savingUpsertsByTeamIDAndSortsByName() throws {
        let library = tempLibrary()
        #expect(try library.all().isEmpty)

        let arsenal = Squad(team: Team(name: "Arsenal"),
                            players: [Player(name: "Winger", number: 7)])
        let madrid = Squad(team: Team(name: "Madrid"))
        try library.save(madrid)
        try library.save(arsenal)
        #expect(try library.all().map(\.team.name) == ["Arsenal", "Madrid"])

        // A second save of the same team replaces it rather than duplicating.
        var edited = arsenal
        edited.players.append(Player(name: "Forward", number: 11))
        try library.save(edited)
        let all = try library.all()
        #expect(all.count == 2)
        #expect(all.first?.players.count == 2)
    }

    @Test func deletingRemovesOnlyThatTeam() throws {
        let library = tempLibrary()
        let madrid = Squad(team: Team(name: "Madrid"))
        let arsenal = Squad(team: Team(name: "Arsenal"))
        try library.save(madrid)
        try library.save(arsenal)
        try library.delete(teamID: madrid.team.id)
        #expect(try library.all().map(\.team.name) == ["Arsenal"])
    }

    @Test func theLibrarySurvivesANewInstance() throws {
        let library = tempLibrary()
        let squad = Squad(team: Team(name: "Madrid"), players: [Player(name: "Striker", number: 9)])
        try library.save(squad)
        let reopened = try TeamLibrary(directory: library.directory).all()
        #expect(reopened == [squad])
    }
}

@Suite("quick matches")
struct QuickMatchTests {
    @Test func placeholdersAreToldApart() {
        #expect(Team.placeholder(.home).abbreviation == "HOM")
        #expect(Team.placeholder(.away).abbreviation == "AWY")
        #expect(Team.placeholder(.home).color != Team.placeholder(.away).color)
    }

    @Test func swappingSidesKeepsEachTeamSheetWithItsTeam() {
        let setup = Fixture.setup
        let swapped = setup.swappingSides()
        #expect(swapped.home == setup.away)
        #expect(swapped.away == setup.home)
        #expect(swapped.squad(for: .home)?.players == setup.squad(for: .away)?.players)
        #expect(swapped.swappingSides() == setup)
    }
}
