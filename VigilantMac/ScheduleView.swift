//
//  ScheduleView.swift
//  Vigilant (macOS)
//
//  View and edit the weekly work windows that gate the schedule mode.
//

import SwiftUI

struct ScheduleView: View {
    @Bindable var controller: AppController
    @Bindable var settings: VigilantSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                masterToggle

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(settings.schedule.days) { day in
                        dayRow(day.weekday)
                        if day.weekday != settings.schedule.days.last?.weekday {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                HStack {
                    Text("Times use this Mac's local time zone.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Defaults") { settings.resetScheduleToDefault() }
                        .controlSize(.small)
                }
            }
            .padding(24)
        }
        .navigationTitle("Schedule")
    }

    // MARK: - Master toggle

    private var masterToggle: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Work schedule").font(.headline)
                Text(controller.store.state.enabled
                     ? "Sentry is on — active only during the enabled windows below, skipping holidays."
                     : "When Sentry is on, it’s active only during the enabled windows below, skipping holidays.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Label(controller.store.state.enabled ? "On" : "Off",
                  systemImage: controller.store.state.enabled ? "checkmark.circle.fill" : "circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(controller.store.state.enabled ? .green : .secondary)
                .font(.title3)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Day row

    private func dayRow(_ weekday: Int) -> some View {
        let binding = dayBinding(weekday)
        let isToday = Calendar.current.component(.weekday, from: Date()) == weekday
        return HStack(spacing: 12) {
            Toggle("", isOn: binding.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()

            HStack(spacing: 6) {
                Text(binding.wrappedValue.name)
                    .font(.body.weight(.medium))
                    .frame(width: 92, alignment: .leading)
                if isToday {
                    Text("TODAY")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }

            Spacer()

            DatePicker("", selection: timeBinding(binding, \.start), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!binding.wrappedValue.isEnabled)
            Text("to").foregroundStyle(.secondary)
            DatePicker("", selection: timeBinding(binding, \.end), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!binding.wrappedValue.isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(binding.wrappedValue.isEnabled ? 1 : 0.55)
    }

    // MARK: - Bindings

    private func dayBinding(_ weekday: Int) -> Binding<DaySchedule> {
        Binding(
            get: {
                settings.schedule.day(forWeekday: weekday)
                    ?? DaySchedule(weekday: weekday, isEnabled: false,
                                   start: .init(hour: 9, minute: 0), end: .init(hour: 17, minute: 0))
            },
            set: { newValue in
                if let idx = settings.schedule.days.firstIndex(where: { $0.weekday == weekday }) {
                    settings.schedule.days[idx] = newValue
                }
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
