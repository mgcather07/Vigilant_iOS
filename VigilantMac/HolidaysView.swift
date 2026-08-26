//
//  HolidaysView.swift
//  Vigilant (macOS)
//
//  Review the holidays Vigilant will pause on, toggle the optional
//  categories, and add your own custom holidays.
//

import SwiftUI

struct HolidaysView: View {
    @Bindable var settings: VigilantSettings
    @State private var showingAdd = false

    private var years: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return [y, y + 1]
    }

    private var upcoming: [(date: Date, name: String)] {
        settings.makeCalendar(years: years).upcoming(limit: 16)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                optionsSection
                upcomingSection
                customSection
            }
            .padding(24)
        }
        .navigationTitle("Holidays")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddHolidaySheet { holiday in
                settings.customHolidays.append(holiday)
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        SectionPanel(title: "Policy", systemImage: "slider.horizontal.3") {
            Toggle(isOn: Binding(
                get: { settings.includeObserved },
                set: { settings.includeObserved = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Observe weekend holidays")
                    Text("Shift Saturday holidays to Friday and Sunday holidays to Monday.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            Text("Optional holidays").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(BusinessCalendar.Optional.allCases) { option in
                Toggle(option.displayName, isOn: optionBinding(option))
                    .toggleStyle(.switch)
            }
        }
    }

    private func optionBinding(_ option: BusinessCalendar.Optional) -> Binding<Bool> {
        Binding(
            get: { settings.optionalHolidays.contains(option) },
            set: { on in
                if on { settings.optionalHolidays.insert(option) }
                else { settings.optionalHolidays.remove(option) }
            }
        )
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        SectionPanel(title: "Upcoming (next \(upcoming.count))", systemImage: "calendar") {
            if upcoming.isEmpty {
                Text("No holidays scheduled.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.offset) { index, item in
                    holidayRow(date: item.date, name: item.name)
                    if index != upcoming.count - 1 { Divider() }
                }
            }
        }
    }

    private func holidayRow(date: Date, name: String) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.callout.weight(.semibold))
                Text("\(date.formatted(.dateTime.weekday(.abbreviated))) · \(date.formatted(.dateTime.year()))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 84, alignment: .leading)

            Text(name).font(.body)
            Spacer()
            if isToday {
                Text("TODAY").font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Custom

    private var customSection: some View {
        SectionPanel(title: "Custom holidays", systemImage: "star") {
            if settings.customHolidays.isEmpty {
                Text("None yet. Use the + button to add your own days off.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.customHolidays) { holiday in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(holiday.name).font(.body.weight(.medium))
                            Text(customSubtitle(holiday)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.customHolidays.removeAll { $0.id == holiday.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 3)
                    if holiday.id != settings.customHolidays.last?.id { Divider() }
                }
            }
        }
    }

    private func customSubtitle(_ h: CustomHoliday) -> String {
        var comps = DateComponents(); comps.month = h.month; comps.day = h.day; comps.year = h.year ?? 2000
        let date = Calendar.current.date(from: comps) ?? Date()
        let md = date.formatted(.dateTime.month(.wide).day())
        return h.year == nil ? "Every year · \(md)" : "\(md), \(h.year!)"
    }
}

// MARK: - Reusable panel

struct SectionPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Add sheet

struct AddHolidaySheet: View {
    var onAdd: (CustomHoliday) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var recurring = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Holiday").font(.title2.bold())

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Company Retreat"))
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Repeat every year", isOn: $recurring)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    onAdd(CustomHoliday(name: name.isEmpty ? "Holiday" : name,
                                        month: c.month ?? 1,
                                        day: c.day ?? 1,
                                        year: recurring ? nil : c.year))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
