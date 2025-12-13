class MenuAddon {
  final String id;
  final String productId;
  final String name;
  final int priceCents;
  final bool isRequired;
  final int? maxQuantity;
  final int? sortOrder;

  const MenuAddon({
    required this.id,
    required this.productId,
    required this.name,
    required this.priceCents,
    this.isRequired = false,
    this.maxQuantity,
    this.sortOrder,
  });

  factory MenuAddon.fromMap(Map<String, dynamic> map) {
    final price = map['price'];
    int priceInCents;
    if (price is num) {
      priceInCents = (price * 100).round();
    } else if (price is String) {
      priceInCents = ((double.tryParse(price) ?? 0) * 100).round();
    } else {
      priceInCents = 0;
    }

    return MenuAddon(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      name: (map['name'] as String?) ?? '',
      priceCents: priceInCents,
      isRequired: map['is_required'] as bool? ?? false,
      maxQuantity: map['max_quantity'] as int?,
      sortOrder: map['sort_order'] as int?,
    );
  }

  bool get isFree => priceCents == 0;
}

