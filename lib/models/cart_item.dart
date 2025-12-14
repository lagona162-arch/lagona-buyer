import 'menu_addon.dart';

class SelectedAddon {
  final String addonId;
  final String name;
  final int priceCents;
  final int quantity;

  const SelectedAddon({
    required this.addonId,
    required this.name,
    required this.priceCents,
    this.quantity = 1,
  });

  int get totalCents => priceCents * quantity;
}

class CartItem {
  final String menuItemId;
  final String name;
  final String? description;
  final String? photoUrl;
  final int priceCents;
  int quantity;
  final List<SelectedAddon> selectedAddons;

  CartItem({
    required this.menuItemId,
    required this.name,
    this.description,
    this.photoUrl,
    required this.priceCents,
    this.quantity = 1,
    this.selectedAddons = const [],
  });

  int get basePriceCents => priceCents * quantity;
  
  int get addonsTotalCents => selectedAddons.fold(
    0, 
    (sum, addon) => sum + addon.totalCents,
  );
  
  int get lineTotalCents => basePriceCents + addonsTotalCents;

  CartItem copyWith({
    String? menuItemId,
    String? name,
    String? description,
    String? photoUrl,
    int? priceCents,
    int? quantity,
    List<SelectedAddon>? selectedAddons,
  }) {
    return CartItem(
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      description: description ?? this.description,
      photoUrl: photoUrl ?? this.photoUrl,
      priceCents: priceCents ?? this.priceCents,
      quantity: quantity ?? this.quantity,
      selectedAddons: selectedAddons ?? this.selectedAddons,
    );
  }

  bool hasSameAddons(List<SelectedAddon> otherAddons) {
    if (selectedAddons.length != otherAddons.length) return false;
    
    final sortedThis = List<SelectedAddon>.from(selectedAddons)
      ..sort((a, b) => a.addonId.compareTo(b.addonId));
    final sortedOther = List<SelectedAddon>.from(otherAddons)
      ..sort((a, b) => a.addonId.compareTo(b.addonId));
    
    for (int i = 0; i < sortedThis.length; i++) {
      if (sortedThis[i].addonId != sortedOther[i].addonId ||
          sortedThis[i].quantity != sortedOther[i].quantity) {
        return false;
      }
    }
    return true;
  }
}

