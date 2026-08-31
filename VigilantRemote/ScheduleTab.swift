//
//  ScheduleTab.swift
//  Vigilant Remote (iOS)
//
//  View and edit the weekly work windows that Sentry follows. Edits are made
//  on a local draft and pushed to CloudKit on Save; the Mac adopts them.
//  Upcoming holidays are shown read-only (edited on the Mac).
//

import SwiftUI

struct ScheduleTab: View {
    @Bindable var model: RemoteModel

    @State private var draft: WorkSchedule?
    @State private var lastSynced: WorkSchedule?

    private var synced: WorkSchedule? { model.store.state.schedule }
    private var holidays: [HolidayItem] { model.store.state.upcomingHolidays }
    private var dirty: Bool { draft != nil && draft != synced }

    var body: some View {
        NavigationStack {
            Group {
                if draft != nil {
                    editor
                } else {
                    ContentUnavailableView(
                        "Waiting for the Mac",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("The schedule appears once the Mac has synced it.")
                    )
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if dirty { Button("Revert") { draft = synced } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { if let d = draft { model.setSchedule(d) } }
                        .disabled(!dirty || model.isBusy)
                }
            }
            .onAppear {
                if draft == nil { draft = synced }
                lastSynced = synced
            }
            .onChange(of: synced) { _, newValue in
                // Adopt a remote update only if the user hasn't diverged locally.
                if draft == lastSynced { draft = newValue }
                lastSynced = newValue
            }
        }
    }

    private var editor: some View {
        List {
            Section("Work windows") {
                ForEach(draft?.days ?? []) { day in
                    dayRow(day.weekday)
                }
            }

            Section {
                Text("Sentry keeps the Mac awake only during the enabled windows, skipping holidays. Times use the Mac’s time zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !holidays.isEmpty {
                Section("Upcoming holidays (skipped)") {
                    ForEach(holidays) { h in
                        HStack {
                            Text(h.name)
                            Spacer()
                            Text(h.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Day row

    private func dayRow(_ weekday: Int) -> some View {
        let day = dayBinding(weekday)
        let isToday = Calendar.current.component(.weekday, from: Date()) == weekday
        return VStack(spacing: 8) {
            Toggle(isOn: day.isEnabled) {
                HStack(spacing: 6) {
                    Text(day.wrappedValue.name).font(.body.weight(.medium))
                    if isToday {
                        Text("TODAY")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
            }

            if day.wrappedValue.isEnabled {
                HStack {
                    DatePicker("", selection: timeBinding(day, \.start), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to").foregroundStyle(.secondary)
                    DatePicker("", selection: timeBinding(day, \.end), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bindings into the draft

    private func dayBinding(_ weekday: Int) -> Binding<DaySchedule> {
        Binding(
            get: {
                draft?.day(forWeekday: weekday)
                    ?? DaySchedule(weekday: weekday, isEnabled: false,
                                   start: .init(hour: 9, minute: 0), end: .init(hour: 17, minute: 0))
            },
            set: { newValue in
                guard var d = draft,
                      let idx = d.days.firstIndex(where: { $0.weekday == weekday }) else { return }
                d.days[idx] = newValue
                draft = d
            }
        )
    }

    private func timeBinding(_ day: Binding<DaySchedule>, _ keyPath: WritableKeyPath<DaySchedule, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                let t = day.wrappedValue[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var updated = day.wrappedValue
                updated[keyPath: keyPath] = TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
                day.wrappedValue = updated
            }
        )
    }
}
