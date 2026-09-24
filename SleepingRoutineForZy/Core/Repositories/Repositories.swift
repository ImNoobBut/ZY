import Foundation
import SwiftData

protocol PreferencesRepository: AnyObject {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences) throws
}

final class PreferencesRepositoryLive: PreferencesRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func load() -> UserPreferences {
        let descriptor = FetchDescriptor<PreferencesEntity>()
        if let entity = try? context.fetch(descriptor).first {
            return entity.toDomain()
        }
        return .default
    }

    func save(_ preferences: UserPreferences) throws {
        let descriptor = FetchDescriptor<PreferencesEntity>()
        if let entity = try context.fetch(descriptor).first {
            entity.apply(preferences)
        } else {
            context.insert(PreferencesEntity(from: preferences))
        }
        try context.save()
    }
}

protocol RoutineRepository: AnyObject {
    func loadActiveRoutine() -> SleepRoutine?
    func save(_ routine: SleepRoutine) throws
    func clearActiveRoutine() throws
}

final class RoutineRepositoryLive: RoutineRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadActiveRoutine() -> SleepRoutine? {
        let descriptor = FetchDescriptor<SleepRoutineEntity>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try? context.fetch(descriptor).first?.toDomain()
    }

    func save(_ routine: SleepRoutine) throws {
        let targetID = routine.id
        let descriptor = FetchDescriptor<SleepRoutineEntity>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let entity = try context.fetch(descriptor).first {
            entity.apply(routine)
        } else {
            context.insert(SleepRoutineEntity(from: routine))
        }
        try context.save()
    }

    func clearActiveRoutine() throws {
        let descriptor = FetchDescriptor<SleepRoutineEntity>()
        let entities = try context.fetch(descriptor)
        for entity in entities {
            context.delete(entity)
        }
        try context.save()
    }
}

protocol AlarmRepository: AnyObject {
    func fetchAll() -> [SleepAlarm]
    func save(_ alarm: SleepAlarm) throws
    func delete(id: UUID) throws
}

final class AlarmRepositoryLive: AlarmRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [SleepAlarm] {
        let descriptor = FetchDescriptor<SleepAlarmEntity>(
            sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute)]
        )
        return (try? context.fetch(descriptor).map { $0.toDomain() }) ?? []
    }

    func save(_ alarm: SleepAlarm) throws {
        let targetID = alarm.id
        let descriptor = FetchDescriptor<SleepAlarmEntity>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let entity = try context.fetch(descriptor).first {
            entity.apply(alarm)
        } else {
            context.insert(SleepAlarmEntity(from: alarm))
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<SleepAlarmEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let entity = try context.fetch(descriptor).first {
            context.delete(entity)
            try context.save()
        }
    }
}

protocol HistoryRepository: AnyObject {
    func fetchRecent(limit: Int) -> [SleepSessionRecord]
    func append(_ record: SleepSessionRecord) throws
    func deleteAll() throws
}

final class HistoryRepositoryLive: HistoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchRecent(limit: Int) -> [SleepSessionRecord] {
        var descriptor = FetchDescriptor<SleepSessionEntity>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor).map { $0.toDomain() }) ?? []
    }

    func append(_ record: SleepSessionRecord) throws {
        context.insert(SleepSessionEntity(from: record))
        try context.save()
    }

    func deleteAll() throws {
        let descriptor = FetchDescriptor<SleepSessionEntity>()
        for entity in try context.fetch(descriptor) {
            context.delete(entity)
        }
        try context.save()
    }
}
