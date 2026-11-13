import DuctusLog
import Foundation
import SwiftData

/// SwiftData container for saved progress. Lives in the app's sandbox
/// (Application Support). Nothing leaves the Mac.
@MainActor
final class ProgressStore {
    let container: ModelContainer
    /// `false` if the on-disk store could not be opened and this session only
    /// keeps progress in memory.
    let isPersistent: Bool

    var context: ModelContext { container.mainContext }

    init() {
        let schema = Schema([LayoutProfile.self, DrillEntry.self, KeyDayEntry.self, UnlockEntry.self])
        do {
            container = try ModelContainer(for: schema)
            isPersistent = true
            Log.success("Progress store ready")
        } catch {
            // Keep the app usable; the user is told progress will not be saved.
            Log.error("Could not open the progress store, using memory only: \(error)")
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            isPersistent = false
        }
    }

    func profile(for layoutID: String) -> LayoutProfile? {
        let id = layoutID
        var descriptor = FetchDescriptor<LayoutProfile>(predicate: #Predicate { $0.layoutID == id })
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            Log.error("Could not load progress for \(layoutID): \(error)")
            return nil
        }
    }

    func insert(_ profile: LayoutProfile) {
        context.insert(profile)
    }

    /// Deletes a profile and, through cascade rules, all its history.
    func delete(_ profile: LayoutProfile) {
        context.delete(profile)
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
            Log.debug("Progress saved")
        } catch {
            Log.error("Could not save progress: \(error)")
        }
    }
}
