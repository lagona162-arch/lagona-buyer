class CartItem {
  final String menuItemId;
  final String name;
  final String? description;
  final String? photoUrl;
  final int priceCents;
  int quantity;

  CartItem({
    required this.menuItemId,
    required this.name,
    this.description,
    this.photoUrl,
    required this.priceCents,
    this.quantity = 1,
  });

  int get lineTotalCents => priceCents * quantity;

  CartItem copyWith({
    String? menuItemId,
    String? name,
    String? description,
    String? photoUrl,
    int? priceCents,
    int? quantity,
  }) {
    return CartItem(
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      description: description ?? this.description,
      photoUrl: photoUrl ?? this.photoUrl,
      priceCents: priceCents ?? this.priceCents,
      quantity: quantity ?? this.quantity,
    );
  }
}

