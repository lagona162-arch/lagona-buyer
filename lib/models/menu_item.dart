class MenuItem {
	final String id;
	final String merchantId;
	final String name;
	final String? description;
	final int priceCents;
	final String? photoUrl;

	const MenuItem({
		required this.id,
		required this.merchantId,
		required this.name,
		this.description,
		required this.priceCents,
		this.photoUrl,
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
		return MenuItem(
			id: map['id'] as String,
			merchantId: map['merchant_id'] as String,
			name: (map['name'] as String?) ?? '',
			description: map['description'] as String?,
			priceCents: priceInCents,
			photoUrl: map['photo_url'] as String?,
		);
	}
}


