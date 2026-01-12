import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/menu_item.dart';

class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  final List<CartItem> _items = [];
  String? _merchantId;

  List<CartItem> get items => List.unmodifiable(_items);
  String? get merchantId => _merchantId;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);
  
  int get totalCents => _items.fold(0, (sum, item) => sum + item.lineTotalCents);

  bool get isEmpty => _items.isEmpty;

  
  bool isDifferentMerchant(String merchantId) {
    return _merchantId != null && _merchantId != merchantId;
  }

  
  void addItem(
    MenuItem menuItem, {
    int quantity = 1,
    List<SelectedAddon> selectedAddons = const [],
  }) {
    
    if (isDifferentMerchant(menuItem.merchantId)) {
      _items.clear();
      _merchantId = menuItem.merchantId;
    } else if (_merchantId == null) {
      _merchantId = menuItem.merchantId;
    }

    // Find existing item with same product ID (regardless of addons)
    final existingIndex = _items.indexWhere(
      (item) => item.menuItemId == menuItem.id,
    );

    if (existingIndex >= 0) {
      // Merge: update quantity and merge addons
      final existingItem = _items[existingIndex];
      
      // Merge addons by addonId, summing quantities
      final mergedAddons = <String, SelectedAddon>{};
      
      // Add existing addons
      for (final addon in existingItem.selectedAddons) {
        mergedAddons[addon.addonId] = SelectedAddon(
          addonId: addon.addonId,
          name: addon.name,
          priceCents: addon.priceCents,
          quantity: addon.quantity,
        );
      }
      
      // Merge new addons
      for (final addon in selectedAddons) {
        if (mergedAddons.containsKey(addon.addonId)) {
          // Add to existing addon quantity
          final existingAddon = mergedAddons[addon.addonId]!;
          mergedAddons[addon.addonId] = SelectedAddon(
            addonId: existingAddon.addonId,
            name: existingAddon.name,
            priceCents: existingAddon.priceCents,
            quantity: existingAddon.quantity + addon.quantity,
          );
    } else {
          // Add new addon
          mergedAddons[addon.addonId] = addon;
        }
      }
      
      // Update the existing item with merged data
      _items[existingIndex] = CartItem(
        menuItemId: existingItem.menuItemId,
        name: existingItem.name,
        description: existingItem.description,
        photoUrl: existingItem.photoUrl,
        priceCents: existingItem.priceCents,
        quantity: existingItem.quantity + quantity,
        selectedAddons: mergedAddons.values.toList(),
      );
    } else {
      // Add new item
      _items.add(CartItem(
        menuItemId: menuItem.id,
        name: menuItem.name,
        description: menuItem.description,
        photoUrl: menuItem.photoUrl,
        priceCents: menuItem.priceCents,
        quantity: quantity,
        selectedAddons: selectedAddons,
      ));
    }

    notifyListeners();
  }

  
  void updateQuantity(String menuItemId, int quantity) {
    if (quantity <= 0) {
      removeItem(menuItemId);
      return;
    }

    final index = _items.indexWhere((item) => item.menuItemId == menuItemId);
    if (index >= 0) {
      _items[index].quantity = quantity;
      notifyListeners();
    }
  }

  
  void removeItem(String menuItemId) {
    _items.removeWhere((item) => item.menuItemId == menuItemId);
    if (_items.isEmpty) {
      _merchantId = null;
    }
    notifyListeners();
  }

  
  void clear() {
    _items.clear();
    _merchantId = null;
    notifyListeners();
  }

  
  CartItem? getItem(String menuItemId) {
    try {
      return _items.firstWhere((item) => item.menuItemId == menuItemId);
    } catch (e) {
      return null;
    }
  }

  
  int getItemQuantity(String menuItemId) {
    final item = getItem(menuItemId);
    return item?.quantity ?? 0;
  }
}

