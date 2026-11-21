import SwiftUI

/// Read-only regional material Price Book (OH / PA / WV yard rates).
struct PriceBookView: View {
    private let catalog = RegionalPriceCatalog.default

    var body: some View {
        List {
            Section(header: Text("Region")) {
                PriceBookRegionBlock(catalog: catalog)
            }
            ForEach(catalog.categories, id: \.self) { category in
                PriceBookCategorySection(category: category, items: catalog.materials(in: category))
            }
        }
        .scrollContentBackground(.hidden)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Price Book")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PriceBookRegionBlock: View {
    let catalog: RegionalPriceCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            regionName
            regionalNaming
            deliveryFees
            concreteShortLoad
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(LiDirtColors.surface)
    }

    private var regionName: some View {
        Text(catalog.region)
            .font(LiDirtTypography.body)
            .foregroundStyle(LiDirtColors.textPrimary)
    }

    private var regionalNaming: some View {
        Text(catalog.notes.regionalNaming)
            .font(LiDirtTypography.caption)
            .foregroundStyle(LiDirtColors.textMuted)
    }

    private var deliveryFees: some View {
        Text(catalog.notes.deliveryFees)
            .font(LiDirtTypography.caption)
            .foregroundStyle(LiDirtColors.textMuted)
    }

    private var concreteShortLoad: some View {
        Text(catalog.notes.concreteShortLoad)
            .font(LiDirtTypography.caption)
            .foregroundStyle(LiDirtColors.textMuted)
    }
}

private struct PriceBookCategorySection: View {
    let category: String
    let items: [PriceCatalogItem]

    var body: some View {
        Section(header: Text(category)) {
            ForEach(items) { item in
                PriceBookItemRow(item: item)
            }
        }
    }
}

private struct PriceBookItemRow: View {
    let item: PriceCatalogItem

    private var priceLine: String {
        item.priceRangeSummary + " · " + item.avgSummary
    }

    private var aliasesLine: String? {
        guard !item.aliases.isEmpty else { return nil }
        return item.aliases.joined(separator: " · ")
    }

    var body: some View {
        content
            .padding(.vertical, 2)
            .listRowBackground(LiDirtColors.surface)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameLabel
            priceLabel
            aliasesLabel
            conversionLabel
        }
    }

    private var nameLabel: some View {
        Text(item.name)
            .font(LiDirtTypography.body)
            .foregroundStyle(LiDirtColors.textPrimary)
    }

    private var priceLabel: some View {
        Text(priceLine)
            .font(LiDirtTypography.caption)
            .foregroundStyle(LiDirtColors.constructionYellow)
    }

    @ViewBuilder
    private var aliasesLabel: some View {
        if let aliasesLine {
            Text(aliasesLine)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
    }

    @ViewBuilder
    private var conversionLabel: some View {
        if let note = item.conversionNote {
            Text(note)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
    }
}
