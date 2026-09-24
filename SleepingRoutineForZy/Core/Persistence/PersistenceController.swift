import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            // Corrupt store recovery: fall back to in-memory so the app never crashes on launch.
            assertionFailure("SwiftData store failed: \(error). Using in-memory container.")
            return makeInMemoryContainer()
        }
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("In-memory SwiftData container failed: \(error)")
        }
    }

    private static var schema: Schema {
        Schema([
            PreferencesEntity.self,
            SleepRoutineEntity.self,
            SleepAlarmEntity.self,
            SleepSessionEntity.self
        ])
    }
}
