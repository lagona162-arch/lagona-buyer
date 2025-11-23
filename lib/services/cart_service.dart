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

  /// Check if cart is for a different merchant
  bool isDifferentMerchant(String merchantId) {
    return _merchantId != null && _merchantId != merchantId;
  }

  /// Add item to cart or increment quantity if already exists
  void addItem(MenuItem menuItem, {int quantity = 1}) {
    // If cart has items from a different merchant, clear it first
    if (isDifferentMerchant(menuItem.merchantId)) {
      _items.clear();
      _merchantId = menuItem.merchantId;
    } else if (_merchantId == null) {
      _merchantId = menuItem.merchantId;
    }

    final existingIndex = _items.indexWhere(
      (item) => item.menuItemId == menuItem.id,
    );

    if (existingIndex >= 0) {
      // Item exists, increase quantity
      _items[existingIndex].quantity += quantity;
    } else {
      // New item, add to cart
      _items.add(CartItem(
        menuItemId: menuItem.id,
        name: menuItem.name,
        description: menuItem.description,
        photoUrl: menuItem.photoUrl,
        priceCents: menuItem.priceCents,
        quantity: quantity,
      ));
    }

    notifyListeners();
  }

  /// Update item quantity
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

  /// Remove item from cart
  void removeItem(String menuItemId) {
    _items.removeWhere((item) => item.menuItemId == menuItemId);
    if (_items.isEmpty) {
      _merchantId = null;
    }
    notifyListeners();
  }

  /// Clear entire cart
  void clear() {
    _items.clear();
    _merchantId = null;
    notifyListeners();
  }

  /// Get item by menu item ID
  CartItem? getItem(String menuItemId) {
    try {
      return _items.firstWhere((item) => item.menuItemId == menuItemId);
    } catch (e) {
      return null;
    }
  }

  /// Get quantity of specific item
  int getItemQuantity(String menuItemId) {
    final item = getItem(menuItemId);
    return item?.quantity ?? 0;
  }
}

