import 'menu_addon.dart';

class MenuItem {
	final String id;
	final String merchantId;
	final String name;
	final String? description;
	final int priceCents;
	final String? photoUrl;
	final String? category;
	final int? sortOrder;
	final List<MenuAddon> addons;

	const MenuItem({
		required this.id,
		required this.merchantId,
		required this.name,
		this.description,
		required this.priceCents,
		this.photoUrl,
		this.category,
		this.sortOrder,
		this.addons = const [],
	});

	factory MenuItem.fromMap(Map<String, dynamic> map) {
		final price = map['price'];
		int priceInCents;
		if (price is num) {
			priceInCents = (price * 100).round();
		} else if (price is String) {
			priceInCents = ((double.tryParse(price) ?? 0) * 100).round();
		} else {
			priceInCents = 0;
		}

		// Parse addons if available
		List<MenuAddon> addonsList = [];
		if (map['addons'] != null) {
			final addonsData = map['addons'] as List?;
			if (addonsData != null && addonsData.isNotEmpty) {
				try {
					addonsList = addonsData
						.map((e) {
							try {
								return MenuAddon.fromMap(Map<String, dynamic>.from(e));
							} catch (e) {
								return null;
							}
						})
						.whereType<MenuAddon>()
						.toList();
					// Sort by sort_order if available
					addonsList.sort((a, b) {
						final aOrder = a.sortOrder ?? 0;
						final bOrder = b.sortOrder ?? 0;
						return aOrder.compareTo(bOrder);
					});
				} catch (e) {
					addonsList = [];
				}
			}
		}

		return MenuItem(
			id: map['id'] as String,
			merchantId: map['merchant_id'] as String,
			name: (map['name'] as String?) ?? '',
			description: map['description'] as String?,
			priceCents: priceInCents,
			photoUrl: map['image_url'] as String? ?? map['photo_url'] as String?,
			category: map['category'] as String?,
			sortOrder: map['sort_order'] as int?,
			addons: addonsList,
		);
	}

	bool get hasAddons => addons.isNotEmpty;
}


