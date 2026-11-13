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

        let bayside = Squad(team: Team(name: "Bayside"),
                            players: [Player(name: "Winger", number: 7)])
        let westfield = Squad(team: Team(name: "Westfield"))
        try library.save(westfield)
        try library.save(bayside)
        #expect(try library.all().map(\.team.name) == ["Bayside", "Westfield"])

        // A second save of the same team replaces it rather than duplicating.
        var edited = bayside
        edited.players.append(Player(name: "Forward", number: 11))
        try library.save(edited)
        let all = try library.all()
        #expect(all.count == 2)
        #expect(all.first?.players.count == 2)
    }

    @Test func deletingRemovesOnlyThatTeam() throws {
        let library = tempLibrary()
        let westfield = Squad(team: Team(name: "Westfield"))
        let bayside = Squad(team: Team(name: "Bayside"))
        try library.save(westfield)
        try library.save(bayside)
        try library.delete(teamID: westfield.team.id)
        #expect(try library.all().map(\.team.name) == ["Bayside"])
    }

    @Test func theLibrarySurvivesANewInstance() throws {
        let library = tempLibrary()
        let squad = Squad(team: Team(name: "Westfield"), players: [Player(name: "Striker", number: 9)])
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
