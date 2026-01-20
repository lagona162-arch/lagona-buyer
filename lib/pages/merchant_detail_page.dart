import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/supabase_service.dart';
import '../services/cart_service.dart';
import '../models/menu_item.dart';
import '../models/menu_addon.dart';
import '../models/cart_item.dart';
import '../models/merchant.dart';
import '../theme/app_colors.dart';
import '../app.dart';
import 'cart_page.dart';

class MerchantDetailPage extends StatefulWidget {
  static const String routeName = '/merchant';
  const MerchantDetailPage({super.key});

  @override
  State<MerchantDetailPage> createState() => _MerchantDetailPageState();
}

class _MerchantDetailPageState extends State<MerchantDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final CartService _cartService = CartService();
  final SupabaseService _service = SupabaseService();
  bool _showMiniMap = false;
  GoogleMapController? _mapController;
  String? _selectedCategory;
  List<String> _categories = [];
  bool _categoriesLoaded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    
    _cartService.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cartService.removeListener(_onCartChanged);
    _animationController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Map<String, List<MenuItem>> _groupProductsByCategory(List<MenuItem> products) {
    final grouped = <String, List<MenuItem>>{};
    for (final product in products) {
      final category = product.category ?? 'Other';
      grouped.putIfAbsent(category, () => []).add(product);
    }
    // Sort categories alphabetically
    final sortedCategories = grouped.keys.toList()..sort();
    return Map.fromEntries(
      sortedCategories.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  Widget _buildCategoryHeader(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _loadCategories(String merchantId) {
    if (_categoriesLoaded) return;
    
    _service.getMerchantCategories(merchantId).then((categories) {
      if (mounted) {
        setState(() {
          _categories = categories;
          _categoriesLoaded = true;
        });
      }
    }).catchError((error) {
      debugPrint('Error loading categories: $error');
      if (mounted) {
        setState(() {
          _categoriesLoaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String merchantId = ModalRoute.of(context)?.settings.arguments as String? ?? '';

    if (merchantId.isEmpty) {
    return Scaffold(
      backgroundColor: AppColors.background,
        body: _buildErrorState('Invalid merchant', Icons.error_outline),
      );
    }

    // Load categories on first build
    if (!_categoriesLoaded) {
      _loadCategories(merchantId);
                }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<Merchant?>(
        future: _service.getMerchantById(merchantId),
                  builder: (context, merchantSnapshot) {
                    final merchant = merchantSnapshot.data;
                    return CustomScrollView(
                      slivers: [
                        _buildAppBar(merchant),
                        
                        if (_showMiniMap)
                          SliverToBoxAdapter(
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _buildMiniMapSection(merchant),
                            ),
                          ),
              
                        SliverToBoxAdapter(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Category Selection
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                      Icons.category,
                                          color: AppColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                  const Text(
                                    'Select Category',
                                    style: TextStyle(
                                      fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                              const SizedBox(height: 16),
                              if (!_categoriesLoaded)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (_categories.isEmpty)
                                const Text(
                                  'No categories available',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                DropdownButtonFormField<String>(
                                  value: _selectedCategory,
                                  decoration: InputDecoration(
                                    labelText: 'Choose a category',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    prefixIcon: const Icon(Icons.restaurant_menu),
                                    filled: true,
                                    fillColor: AppColors.inputBackground,
                                  ),
                                  items: _categories.map((category) {
                                    return DropdownMenuItem<String>(
                                      value: category,
                                      child: Text(
                                        category,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  isExpanded: true,
                                  onChanged: (category) {
                                    setState(() {
                                      _selectedCategory = category;
                                    });
                                  },
                                  hint: const Text('Select a category to view products'),
                                ),
                                ],
                              ),
                            ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Products Section (only shown when category is selected)
              if (_selectedCategory != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildProductsSection(merchantId, _selectedCategory!),
                  ),
                )
              else if (_categoriesLoaded && _categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: AppColors.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Select a category above to view products',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                          ),
                        ),
                      ],
                    );
                  },
      ),
                );
  }

  Widget _buildProductsSection(String merchantId, String category) {
    return FutureBuilder<List<MenuItem>>(
      future: _service.getMerchantProductsByCategory(merchantId, category),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error loading products: ${snapshot.error}',
              style: const TextStyle(color: AppColors.error),
            ),
          );
        }
        
        final products = snapshot.data ?? [];
        
        if (products.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_outlined,
                    size: 64,
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No products in this category',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$category (${products.length})',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...products.asMap().entries.map((itemEntry) {
              return _buildMenuItemCard(
                itemEntry.value,
                itemEntry.key,
              );
            }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildMiniMapSection(Merchant? merchant) {
    if (merchant?.latitude == null || merchant?.longitude == null) {
      return Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.location_off,
              color: AppColors.textSecondary,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Location not available',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border.withOpacity(0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (merchant?.address != null)
                    Expanded(
                      flex: 2,
                      child: Text(
                        merchant!.address!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ),
            
            SizedBox(
              height: 200,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(merchant!.latitude!, merchant!.longitude!),
                  zoom: 15,
                ),
                markers: {
                  Marker(
                    markerId: MarkerId(merchant.id),
                    position: LatLng(merchant.latitude!, merchant.longitude!),
                    infoWindow: InfoWindow(
                      title: merchant.name,
                      snippet: merchant.address,
                    ),
                  ),
                },
                zoomControlsEnabled: true,
                myLocationButtonEnabled: false,
                mapType: MapType.normal,
                onMapCreated: (controller) {
                  _mapController = controller;
                },
              ),
            ),
          ],
        ),
            ),
    );
  }

  Widget _buildAppBar(Merchant? merchant) {
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      backgroundColor: AppColors.primary,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_showMiniMap ? 0.3 : 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _showMiniMap ? Icons.map : Icons.map_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          tooltip: _showMiniMap ? 'Hide map' : 'Show map',
          onPressed: () {
            setState(() {
              _showMiniMap = !_showMiniMap;
            });
            
            if (_showMiniMap && merchant != null && merchant!.latitude != null && merchant!.longitude != null) {
              
              Future.delayed(const Duration(milliseconds: 100), () {
                if (_mapController != null && mounted) {
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(merchant!.latitude!, merchant!.longitude!),
                      15,
                    ),
                  );
                }
              });
            }
          },
        ),
        
        ListenableBuilder(
          listenable: _cartService,
          builder: (context, _) {
            final cartCount = _cartService.itemCount;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shopping_cart, color: Colors.white, size: 20),
                  ),
                  onPressed: () {
                    if (cartCount > 0) {
                      Navigator.of(context).pushNamed(CartPage.routeName);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Your cart is empty'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                if (cartCount > 0)
                  Positioned(
                      right: 4,
                      top: 4,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Center(
                          child: Text(
                            cartCount > 99 ? '99+' : cartCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary,
                AppColors.primaryDark,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: merchant?.photoUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  merchant!.photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.store, color: Colors.white),
                                ),
                              )
                            : const Icon(Icons.store, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              merchant?.name ?? 'Merchant',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (merchant?.address != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.white70,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      merchant!.address!,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemCard(MenuItem item, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            debugPrint('Product card tapped for ${item.name}');
            _showAddToCartDialog(item);
          },
          borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: item.photoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          item.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.restaurant,
                            color: AppColors.primary,
                            size: 32,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.restaurant,
                        color: AppColors.primary,
                        size: 32,
                      ),
              ),
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '₱${(item.priceCents / 100).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              debugPrint('Add button tapped for ${item.name}');
                              _showAddToCartDialog(item);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 160,
          floating: false,
          pinned: true,
          backgroundColor: AppColors.primary,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                ),
              ),
            ),
          ),
        ),
        const SliverFillRemaining(
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message, IconData icon) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 160,
          floating: false,
          pinned: true,
          backgroundColor: AppColors.primary,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 160,
          floating: false,
          pinned: true,
          backgroundColor: AppColors.primary,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 64,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No menu items available',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check back later for new items',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddToCartDialog(MenuItem item) {
    // Note: we intentionally do NOT prefill the quantity selector from cart quantity.
    // The modal should always start fresh (quantity=1) when adding from the menu.
    if (_cartService.isDifferentMerchant(item.merchantId)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Different Merchant'),
          content: const Text(
            'You have items from another merchant in your cart. Adding this item will clear your current cart. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showQuantitySelector(item);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      return;
    }

    _showQuantitySelector(item);
  }

  void _showFullScreenImage(String imageUrl, String productName) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final screenWidth = mediaQuery.size.width;
        final screenHeight = mediaQuery.size.height;
        final topPadding = mediaQuery.padding.top;
        final bottomPadding = mediaQuery.padding.bottom;
        
        // Responsive font sizes based on screen width
        final titleFontSize = screenWidth < 360 ? 14.0 : 16.0;
        final hintFontSize = screenWidth < 360 ? 10.0 : 12.0;
        
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: screenWidth,
            height: screenHeight,
            child: SafeArea(
              child: Stack(
                children: [
                  // Full screen image with zoom capability
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          padding: EdgeInsets.all(screenWidth < 360 ? 24 : 40),
                          color: Colors.black54,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: screenWidth < 360 ? 48 : 64,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Failed to load image',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Product name at the bottom - responsive positioning
                  Positioned(
                    bottom: bottomPadding + 20,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth < 360 ? 12 : 16,
                        vertical: screenWidth < 360 ? 8 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        productName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Close button - responsive positioning
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Container(
                        padding: EdgeInsets.all(screenWidth < 360 ? 6 : 8),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: screenWidth < 360 ? 20 : 24,
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  // Hint text - responsive positioning
                  Positioned(
                    top: 16,
                    left: 8,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth < 360 ? 8 : 12,
                        vertical: screenWidth < 360 ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.pinch,
                            color: Colors.white70,
                            size: screenWidth < 360 ? 14 : 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pinch to zoom',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: hintFontSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQuantitySelector(MenuItem item) {
    final currentQuantity = _cartService.getItemQuantity(item.id);
    // Always start at 1 when opening from the menu (avoid "sticky" quantity).
    // CartService.addItem() already merges by adding to existing quantity.
    int quantity = 1;
    final Map<String, int> selectedAddons = {};
    
    // Initialize required addons with quantity 1
    if (item.hasAddons) {
      for (final addon in item.addons) {
        if (addon.isRequired) {
          selectedAddons[addon.id] = 1;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Large product image section
              Builder(
                builder: (context) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  // Large image that takes most of the width
                  final imageHeight = screenWidth < 360 ? 180.0 : (screenWidth < 400 ? 200.0 : 220.0);
                  final titleFontSize = screenWidth < 360 ? 18.0 : 20.0;
                  final priceFontSize = screenWidth < 360 ? 16.0 : 18.0;
                  final descFontSize = screenWidth < 360 ? 13.0 : 14.0;
                  final horizontalPadding = screenWidth < 360 ? 16.0 : 20.0;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Large product image
                      if (item.photoUrl != null)
                        GestureDetector(
                          onTap: () => _showFullScreenImage(item.photoUrl!, item.name),
                          child: Container(
                            margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            height: imageHeight,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(
                                    item.photoUrl!,
                                    width: double.infinity,
                                    height: imageHeight,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Icon(
                                        Icons.restaurant,
                                        color: AppColors.primary,
                                        size: 64,
                                      ),
                                    ),
                                  ),
                                ),
                                // Zoom hint overlay
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.zoom_in,
                                          color: Colors.white,
                                          size: screenWidth < 360 ? 14 : 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tap to zoom',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: screenWidth < 360 ? 10 : 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.restaurant,
                              color: AppColors.primary,
                              size: 48,
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 16),
                      
                      // Product details below image
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: TextStyle(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '₱${(item.priceCents / 100).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: priceFontSize,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (item.description != null && item.description!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                item.description!,
                                style: TextStyle(
                                  fontSize: descFontSize,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Divider(height: 1),
              
              // Addons section
              if (item.hasAddons)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add-ons',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...item.addons.map((addon) {
                        final isSelected = selectedAddons.containsKey(addon.id);
                        final addonQuantity = selectedAddons[addon.id] ?? 0;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected 
                                    ? AppColors.primary 
                                    : AppColors.border,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: isSelected 
                                  ? AppColors.primary.withOpacity(0.05)
                                  : Colors.transparent,
                            ),
                            child: CheckboxListTile(
                              value: isSelected || addon.isRequired,
                              onChanged: addon.isRequired 
                                  ? null 
                                  : (value) {
                                      setModalState(() {
                                        if (value == true) {
                                          selectedAddons[addon.id] = 1;
                                        } else {
                                          selectedAddons.remove(addon.id);
                                        }
                                      });
                                    },
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      addon.name,
                                      style: TextStyle(
                                        fontWeight: isSelected 
                                            ? FontWeight.w600 
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    addon.isFree 
                                        ? 'Free' 
                                        : '₱${(addon.priceCents / 100).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: addon.isFree 
                                          ? AppColors.success 
                                          : AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              secondary: (isSelected || addon.isRequired)
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                                              onPressed: (addonQuantity > 1 && !addon.isRequired) || 
                                                         (addonQuantity > 1 && addon.isRequired)
                                                  ? () {
                                                      setModalState(() {
                                                        selectedAddons[addon.id] = 
                                                            (selectedAddons[addon.id] ?? 1) - 1;
                                                      });
                                                    }
                                                  : null,
                                            ),
                                            Text(
                                              '${selectedAddons[addon.id] ?? 1}',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, size: 20),
                                              onPressed: () {
                                                setModalState(() {
                                                  final maxQty = addon.maxQuantity ?? 10;
                                                  if ((selectedAddons[addon.id] ?? 1) < maxQty) {
                                                    selectedAddons[addon.id] = 
                                                        (selectedAddons[addon.id] ?? 1) + 1;
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        )
                                      : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Quantity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        
                        Container(
                          decoration: BoxDecoration(
                            color: quantity > 1
                                ? AppColors.primary.withOpacity(0.1)
                                : Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.remove,
                              color: quantity > 1
                                  ? AppColors.primary
                                  : Colors.grey[400],
                              size: 20,
                            ),
                            onPressed: quantity > 1
                                ? () {
                                    setModalState(() => quantity--);
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          quantity.toString(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.add,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            onPressed: () {
                              setModalState(() => quantity++);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Convert selected addons to SelectedAddon list
                      final selectedAddonsList = selectedAddons.entries.map((entry) {
                        final addon = item.addons.firstWhere((a) => a.id == entry.key);
                        return SelectedAddon(
                          addonId: addon.id,
                          name: addon.name,
                          priceCents: addon.priceCents,
                          quantity: entry.value,
                        );
                      }).toList();
                      
                      // Calculate total price including addons
                      final basePrice = item.priceCents * quantity;
                      final addonsPrice = selectedAddonsList.fold(
                        0,
                        (sum, addon) => sum + addon.totalCents,
                      );
                      final totalPrice = (basePrice + addonsPrice) / 100;
                      
                      _cartService.addItem(
                        item,
                        quantity: quantity,
                        selectedAddons: selectedAddonsList,
                      );
                      
                      Navigator.of(context).pop();
                      
                      if (mounted) {
                        setState(() {});
                      }
                      
                      // Show snackbar after modal is closed to ensure proper context
                      if (mounted) {
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (!mounted) return;
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            quantity > 1
                                ? '${item.name} (x$quantity) added to cart!'
                                : '${item.name} added to cart!',
                          ),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          duration: const Duration(seconds: 2),
                          action: _cartService.itemCount > 0
                              ? SnackBarAction(
                                  label: 'View Cart',
                                  textColor: Colors.white,
                                  onPressed: () {
                                        // Use the global navigator key to avoid deactivated widget context issues
                                        final navigator = BuyerApp.navigatorKey.currentState;
                                        if (navigator != null) {
                                          navigator.pushNamed(CartPage.routeName);
                                        }
                                  },
                                )
                              : null,
                        ),
                      );
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        final basePrice = item.priceCents * quantity;
                        final addonsPrice = selectedAddons.entries.fold<int>(
                          0,
                          (sum, entry) {
                            final addon = item.addons.firstWhere((a) => a.id == entry.key);
                            return sum + (addon.priceCents * entry.value);
                          },
                        );
                        final totalPrice = (basePrice + addonsPrice) / 100;
                        
                        return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shopping_cart, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          currentQuantity > 0
                                  ? 'Add More - ₱${totalPrice.toStringAsFixed(2)}'
                                  : 'Add to Cart - ₱${totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}


