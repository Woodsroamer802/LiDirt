import SwiftUI

/// Read-only regional material Price Book (OH / PA / WV yard rates).
struct PriceBookView: View {
    private let catalog = RegionalPriceCatalog.default

    var body: some View {
        List {
            regionSection
            ForEach(catalog.categories, id: \.self) { category in
                Section {
                    ForEach(catalog.materials(in: category)) { item in
                        PriceBookItemRow(item: item)
                    }
                } header: {
                    Text(category)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Price Book")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var regionSection: some View {
        Section {
            Text(catalog.region)
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textPrimary)
                .listRowBackground(LiDirtColors.gunmetalElevated)

            Text(catalog.notes.regionalNaming)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
                .listRowBackground(LiDirtColors.gunmetalElevated)

            Text(catalog.notes.deliveryFees)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
                .listRowBackground(LiDirtColors.gunmetalElevated)

            Text(catalog.notes.concreteShortLoad)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
                .listRowBackground(LiDirtColors.gunmetalElevated)
        } header: {
            Text("Region")
        }
    }
}

private struct PriceBookItemRow: View {
    let item: PriceCatalogItem

    private var priceLine: String {
        "\(item.priceRangeSummary) · \(item.avgSummary)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textPrimary)

            Text(priceLine)
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
        .listRowBackground(LiDirtColors.gunmetalElevated)
    }
}
