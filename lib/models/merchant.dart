class Merchant {
	final String id;
	final String name;
	final String? address;
	final double? latitude;
	final double? longitude;
	final String? photoUrl;

	const Merchant({
		required this.id,
		required this.name,
		this.address,
		this.latitude,
		this.longitude,
		this.photoUrl,
	});

	factory Merchant.fromMap(Map<String, dynamic> map) {
		return Merchant(
			id: map['id'] as String,
			name: (map['business_name'] as String?) ?? '',
			address: map['address'] as String?,
			latitude: (map['latitude'] as num?)?.toDouble(),
			longitude: (map['longitude'] as num?)?.toDouble(),
			photoUrl: map['preview_image'] as String?,
		);
	}
}


