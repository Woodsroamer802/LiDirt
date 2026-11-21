import SwiftUI

/// Read-only regional material Price Book (OH / PA / WV yard rates).
struct PriceBookView: View {
    private let catalog = RegionalPriceCatalog.default

    var body: some View {
        List {
            Section {
                Text(catalog.region)
                    .font(LiDirtTypography.body)
                    .foregroundStyle(LiDirtColors.textPrimary)
                Text(catalog.notes.regionalNaming)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
                Text(catalog.notes.deliveryFees)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
                Text(catalog.notes.concreteShortLoad)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
            } header: {
                Text("Region")
            }

            ForEach(catalog.categories, id: \.self) { category in
                Section(category) {
                    ForEach(catalog.materials(in: category)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(LiDirtTypography.body)
                                .foregroundStyle(LiDirtColors.textPrimary)
                            Text(item.priceRangeSummary + " · " + item.avgSummary)
                                .font(LiDirtTypography.caption)
                                .foregroundStyle(LiDirtColors.constructionYellow)
                            if !item.aliases.isEmpty {
                                Text(item.aliases.joined(separator: " · "))
                                    .font(LiDirtTypography.caption)
                                    .foregroundStyle(LiDirtColors.textMuted)
                            }
                            if let note = item.conversionNote {
                                Text(note)
                                    .font(LiDirtTypography.caption)
                                    .foregroundStyle(LiDirtColors.textMuted)
                            }
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(LiDirtColors.surface)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Price Book")
        .navigationBarTitleDisplayMode(.inline)
    }
}
