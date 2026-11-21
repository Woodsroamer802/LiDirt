import SwiftUI

/// Simple browsable Price Book from Overview.
struct PriceBookView: View {
    private let catalog = RegionalPriceCatalog.default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(catalog.region)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)

                ForEach(catalog.categories, id: \.self) { category in
                    categoryBlock(category)
                }
            }
            .padding(20)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Price Book")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryBlock(_ category: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category)
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.constructionYellow)

            ForEach(catalog.materials(in: category)) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: PriceCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text(item.lineSummary)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LiDirtColors.gunmetalElevated)
        )
    }
}
