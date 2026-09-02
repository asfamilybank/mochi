import Foundation
import Testing

@testable import MochiCore

@Suite struct BuiltInScriptsTests {
    @Test func includesAtLeastOneOfficiallyMaintainedAdapterScript() {
        #expect(!BuiltInScripts.all.isEmpty)
    }

    @Test func everyBuiltInScriptHasNonEmptyIdDisplayNameAndSource() {
        for script in BuiltInScripts.all {
            #expect(!script.id.isEmpty)
            #expect(!script.displayName.isEmpty)
            #expect(!script.source.isEmpty)
        }
    }

    @Test func builtInScriptIdsAreUnique() {
        let ids = BuiltInScripts.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
