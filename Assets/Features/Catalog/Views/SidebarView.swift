//
//  SidebarView.swift
//  Assets
//
//  Sidebar showing asset categories and groups
//

import SwiftUI

struct SidebarView: View {
    let viewModel: CatalogViewModel
    @State private var isGroupsExpanded = true

    var body: some View {
        List {
            // Categories Section
            Section {
                ForEach(viewModel.categories) { category in
                    SidebarRow(
                        title: category.name,
                        icon: category.iconName,
                        isSelected: viewModel.selectedGroup == nil && viewModel.selectedCategory == category
                    )
                    .onTapGesture {
                        viewModel.selectCategory(category)
                    }
                }
            } header: {
                Text("Categories")
                    .sidebarSectionHeader()
            }

            // Groups Section (collapsible)
            Section(isExpanded: $isGroupsExpanded) {
                ForEach(viewModel.groups) { group in
                    SidebarRow(
                        title: group.name,
                        icon: "folder",
                        isSelected: viewModel.selectedGroup?.name == group.name
                    )
                    .onTapGesture {
                        if viewModel.selectedGroup?.name == group.name {
                            viewModel.selectGroup(nil)
                        } else {
                            viewModel.selectGroup(group)
                        }
                    }
                }
            } header: {
                Text("Groups")
                    .sidebarSectionHeader()
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            catalogInfoView
        }
    }

    @ViewBuilder
    private var catalogInfoView: some View {
        if !viewModel.catalogName.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.catalogName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(viewModel.assets.count) assets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.selection)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Section Header Style

extension View {
    func sidebarSectionHeader() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
