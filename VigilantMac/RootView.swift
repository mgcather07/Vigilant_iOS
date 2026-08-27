//
//  RootView.swift
//  Vigilant (macOS)
//
//  The full-app shell: a sidebar (NavigationSplitView) with Overview,
//  Monitor, Schedule, and Holidays.
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, monitor, schedule, holidays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .monitor:  return "Monitor"
        case .schedule: return "Schedule"
        case .holidays: return "Holidays"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .monitor:  return "chart.bar.xaxis"
        case .schedule: return "calendar.badge.clock"
        case .holidays: return "party.popper"
        }
    }
}

struct RootView: View {
    @Bindable var controller: AppController
    @State private var selection: SidebarItem? = .overview
    @State private var settings = VigilantSettings.shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detail
                .frame(minWidth: 460, minHeight: 560)
        }
        .frame(minWidth: 760, minHeight: 620)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { brandHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { powerFooter }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(controller.isActive ? Color.green.gradient : Color.secondary.gradient)
                    .frame(width: 34, height: 34)
                Image(systemName: controller.isActive ? "eye.fill" : "eye")
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Vigilant").font(.headline)
                Text(controller.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var powerFooter: some View {
        VStack(spacing: 8) {
            Divider()
            Toggle(isOn: Binding(
                get: { controller.store.state.enabled },
                set: { _ in controller.toggleEnabled() }
            )) {
                Label(controller.store.state.enabled ? "Sentry on duty" : "Sentry off duty",
                      systemImage: controller.store.state.enabled ? "bolt.fill" : "bolt.slash")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview: OverviewView(controller: controller)
        case .monitor:  MonitorView(controller: controller)
        case .schedule: ScheduleView(controller: controller, settings: settings)
        case .holidays: HolidaysView(settings: settings)
        }
    }
}
