import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/maps_config.dart';
import '../services/supabase_service.dart';
import '../services/cart_service.dart';
import '../theme/app_colors.dart';
import '../models/cart_item.dart';
import '../models/merchant.dart';
import '../utils/geo.dart';
import 'order_tracking_page.dart';
import 'merchant_list_page.dart';

class CheckoutPage extends StatefulWidget {
  static const String routeName = '/checkout';
  final String? merchantId;
  const CheckoutPage({super.key, this.merchantId});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final CartService _cartService = CartService();
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  List<Map<String, String>> _predictions = [];
  LatLng? _selectedLatLng;
  String? _selectedAddress;
  GoogleMapController? _mapController;
  GoogleMapController? _previewMapController; // For the preview map
  bool _isPlacingOrder = false;
  bool _isLoading = true;
  Map<String, dynamic>? _customerData;
  Merchant? _merchant;
  double? _deliveryFee;

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
    _loadMerchantData();
    _checkExistingFoodOrder();
  }

  Future<void> _checkExistingFoodOrder() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final existingDeliveries = await _supabaseService.getCustomerDeliveries(
        customerId: user.id,
      );
      
      final hasActiveFoodOrder = existingDeliveries.any((d) {
        final status = (d['status']?.toString().toLowerCase() ?? '').trim();
        final type = d['type']?.toString().toLowerCase() ?? '';
        final isFood = type == 'food' || type == '';
        final isActive = status != 'delivered' && 
                        status != 'completed' && 
                        status != 'cancelled';
        return isFood && isActive;
      });
      
      if (hasActiveFoodOrder && mounted) {
        // Show warning banner
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '⚠️ You already have an active food order. Please complete or cancel it first.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'View',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed(
                      '/service-selection',
                    );
                  },
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error checking existing food order: $e');
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _searchController.dispose();
    _notesController.dispose();
    _mapController?.dispose();
    _previewMapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final customerData = await Supabase.instance.client
          .from('customers')
          .select('address, latitude, longitude')
          .eq('id', user.id)
          .maybeSingle();

      if (customerData != null) {
        setState(() {
          _customerData = customerData;
          final address = customerData['address'] as String?;
          final lat = customerData['latitude'] as double?;
          final lng = customerData['longitude'] as double?;
          
          if (address != null && address.isNotEmpty) {
            _addressController.text = address;
            _selectedAddress = address;
          }
          
          if (lat != null && lng != null) {
            _selectedLatLng = LatLng(lat, lng);
            _calculateDeliveryFee();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading customer data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMerchantData() async {
    final merchantId = widget.merchantId ?? _cartService.merchantId;
    if (merchantId == null) return;

    try {
      final merchant = await _supabaseService.getMerchantById(merchantId);
      if (merchant != null) {
        setState(() {
          _merchant = merchant;
          _calculateDeliveryFee();
        });
      }
    } catch (e) {
      debugPrint('Error loading merchant data: $e');
    }
  }

  void _calculateDeliveryFee() {
    if (_merchant == null || _selectedLatLng == null) {
      setState(() => _deliveryFee = null);
      return;
    }

    if (_merchant!.latitude == null || _merchant!.longitude == null) {
      setState(() => _deliveryFee = null);
      return;
    }

    // Use haversine formula from utils for accurate distance calculation
    final distance = haversineKm(
      _merchant!.latitude!,
      _merchant!.longitude!,
      _selectedLatLng!.latitude,
      _selectedLatLng!.longitude,
    );

    debugPrint('📍 Delivery distance calculated: ${distance.toStringAsFixed(2)} km');
    
    // Delivery fee calculation:
    // Base fee: ₱55 for first km
    // Additional fee: ₱10 per km after the first km (rounded up)
    double fee = 55.0; 
    if (distance > 1.0) {
      // Calculate additional kilometers beyond the first km
      // Round up to charge for partial kilometers
      final additionalKm = (distance - 1.0).ceil(); 
      fee += additionalKm * 10.0;
      debugPrint('💰 Additional km: $additionalKm, Fee: ₱${(additionalKm * 10.0).toStringAsFixed(2)}');
    }

    debugPrint('💰 Total delivery fee: ₱${fee.toStringAsFixed(2)}');

    setState(() {
      _deliveryFee = fee;
    });
  }

  Future<void> _fetchAutocomplete(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': input,
          'key': MapsConfig.apiKey,
          'components': 'country:ph',
        },
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final preds = ((data['predictions'] as List?) ?? [])
            .map((p) => {
                  'description': p['description'] as String,
                  'place_id': p['place_id'] as String,
                })
            .toList();
        setState(() => _predictions = preds);
      }
    } catch (e) {
      debugPrint('Error fetching autocomplete: $e');
    }
  }

  Future<void> _selectPlace(String placeId, String description) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': placeId,
          'key': MapsConfig.apiKey,
          'fields': 'geometry/location,formatted_address',
        },
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final loc = data['result']['geometry']['location'] as Map<String, dynamic>;
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        
        setState(() {
          _selectedLatLng = LatLng(lat, lng);
          _selectedAddress = data['result']['formatted_address'] as String? ?? description;
          _addressController.text = _selectedAddress!;
          _searchController.text = _selectedAddress!;
          _predictions = [];
        });
        _calculateDeliveryFee();
        
        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17),
          );
        }
      }
    } catch (e) {
      debugPrint('Error selecting place: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission was permanently denied')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);
      
      
      await _reverseGeocode(latLng);
      
      setState(() {
        _selectedLatLng = latLng;
      });
      _calculateDeliveryFee();

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(latLng, 17),
        );
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '${latLng.latitude},${latLng.longitude}',
          'key': MapsConfig.apiKey,
          'result_type': 'street_address|premise|route',
        },
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final address = results.first['formatted_address'] as String?;
          if (address != null && mounted) {
            setState(() {
              _selectedAddress = address;
              _addressController.text = address;
              _searchController.text = address;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
    }
  }

  Future<void> _openMapModal() async {
    final initialPosition = _selectedLatLng ?? 
        (_customerData != null && _customerData!['latitude'] != null && _customerData!['longitude'] != null
            ? LatLng(
                _customerData!['latitude'] as double,
                _customerData!['longitude'] as double,
              )
            : const LatLng(14.5995, 120.9842)); // Default to Manila
    
    final result = await showDialog<LatLng>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Select Delivery Location',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _MapSelector(
                  initialPosition: initialPosition,
                  isPickup: false,
                  onLocationSelected: (latLng) {
                    Navigator.of(context).pop(latLng);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    
    if (result != null) {
      await _updateLocationFromMap(result);
    }
  }

  Future<void> _updateLocationFromMap(LatLng latLng) async {
    setState(() {
      _selectedLatLng = latLng;
    });

    // Reverse geocode to get address
    await _reverseGeocode(latLng);
    
    // Update delivery fee
    _calculateDeliveryFee();
    
    // Update preview map camera
    if (_previewMapController != null) {
      _previewMapController!.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16),
      );
    }
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a delivery location'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to place an order'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      // Check for existing active food deliveries
      final existingDeliveries = await _supabaseService.getCustomerDeliveries(
        customerId: user.id,
      );
      
      final hasActiveFoodOrder = existingDeliveries.any((d) {
        final status = (d['status']?.toString().toLowerCase() ?? '').trim();
        final type = d['type']?.toString().toLowerCase() ?? '';
        final isFood = type == 'food' || type == '' || type == null;
        final isActive = status != 'delivered' && 
                        status != 'completed' && 
                        status != 'cancelled';
        return isFood && isActive;
      });
      
      if (hasActiveFoodOrder) {
        if (mounted) {
          setState(() => _isPlacingOrder = false);
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Active Food Order'),
              content: const Text(
                'You already have an active food order in progress.\n\n'
                'Please wait for it to complete or cancel it before placing another food order.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
      
      final address = _addressController.text.trim();
      if (address.isNotEmpty && _selectedLatLng != null) {
        await _supabaseService.updateCustomerAddress(
          customerId: user.id,
          address: address,
          latitude: _selectedLatLng!.latitude,
          longitude: _selectedLatLng!.longitude,
        );
      }

      
      final merchantId = widget.merchantId ?? _cartService.merchantId;
      if (merchantId == null) {
        throw Exception('Merchant ID is required');
      }
      
      // Prepare order items with add-ons
      final orderItems = _cartService.items.map((item) {
        final addonsList = item.selectedAddons.map((addon) {
          return {
            'addon_id': addon.addonId,
            'name': addon.name,
            'price_cents': addon.priceCents,
            'quantity': addon.quantity,
          };
        }).toList();
        
        debugPrint('🛒 Preparing order item: ${item.name}');
        debugPrint('   - Menu Item ID: ${item.menuItemId}');
        debugPrint('   - Quantity: ${item.quantity}');
        debugPrint('   - Price (cents): ${item.priceCents}');
        debugPrint('   - Add-ons: ${addonsList.length}');
        if (addonsList.isNotEmpty) {
          for (final addon in addonsList) {
            final addonPriceCents = addon['price_cents'] as int;
            debugPrint('      ➕ ${addon['name']} x${addon['quantity']} (₱${(addonPriceCents / 100).toStringAsFixed(2)} each)');
          }
        }
        
        return {
          'menu_item_id': item.menuItemId,
          'name': item.name,
          'price_cents': item.priceCents,
          'quantity': item.quantity,
          'addons': addonsList,
        };
      }).toList();
      
      debugPrint('📤 Sending ${orderItems.length} item(s) to createOrder...');
      
      final orderId = await _supabaseService.createOrder(
        customerId: user.id,
        merchantId: merchantId,
        items: orderItems,
        deliveryAddress: address,
        deliveryLatitude: _selectedLatLng!.latitude,
        deliveryLongitude: _selectedLatLng!.longitude,
        deliveryNotes: _notesController.text.trim(),
        deliveryFee: _deliveryFee,
      );
      
      debugPrint('✅ Order created successfully! Order ID: $orderId');

      
      _cartService.clear();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          OrderTrackingPage.routeName,
          (route) => route.settings.name == MerchantListPage.routeName || route.isFirst,
          arguments: orderId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPlacingOrder = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: $e'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Menu',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cart',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check Out',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Checkout'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListenableBuilder(
          listenable: _cartService,
          builder: (context, _) {
            final items = _cartService.items;
            final subtotal = _cartService.totalCents;
            final deliveryFeeCents = (_deliveryFee ?? 0.0) * 100;
            final total = subtotal + deliveryFeeCents.toInt();

            return Column(
              children: [
                _buildProgressIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        
                        Text(
                          'Delivery Address',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Single address field that serves both search and display
                        TextFormField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText: 'Delivery Address',
                            hintText: 'Search address or tap map icon to select location',
                            prefixIcon: const Icon(Icons.location_on),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.my_location),
                                  onPressed: _getCurrentLocation,
                                  tooltip: 'Use current location',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.map),
                                  onPressed: () => _openMapModal(),
                                  tooltip: 'Select on map',
                                ),
                              ],
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          maxLines: 2,
                          onChanged: (value) {
                            // Update search controller for autocomplete
                            _searchController.text = value;
                            _fetchAutocomplete(value);
                            // Update selected address
                            setState(() {
                              _selectedAddress = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty || _selectedLatLng == null) {
                              return 'Please select a delivery location';
                            }
                            return null;
                          },
                        ),
                        
                        // Autocomplete suggestions
                        if (_predictions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _predictions.length > 5 ? 5 : _predictions.length,
                              itemBuilder: (context, index) {
                                final prediction = _predictions[index];
                                return ListTile(
                                  leading: const Icon(Icons.location_on, color: AppColors.primary),
                                  title: Text(prediction['description']!),
                                  onTap: () {
                                    _selectPlace(
                                      prediction['place_id']!,
                                      prediction['description']!,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        
                        const SizedBox(height: 16),
                        
                        // Map Preview
                        GestureDetector(
                          onTap: () => _openMapModal(),
                          child: Container(
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border, width: 2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  if (_selectedLatLng == null)
                                    Container(
                                      color: Colors.grey[200],
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.map,
                                              size: 48,
                                              color: AppColors.textSecondary,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Tap to select location',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    GoogleMap(
                                      key: ValueKey(_selectedLatLng?.toString() ?? 'map'),
                                      initialCameraPosition: CameraPosition(
                                        target: _selectedLatLng!,
                                        zoom: 15,
                                      ),
                                      markers: {
                                        Marker(
                                          markerId: const MarkerId('delivery'),
                                          position: _selectedLatLng!,
                                          icon: BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueRed,
                                          ),
                                        ),
                                      },
                                      zoomGesturesEnabled: false,
                                      scrollGesturesEnabled: false,
                                      rotateGesturesEnabled: false,
                                      tiltGesturesEnabled: false,
                                      myLocationButtonEnabled: false,
                                      zoomControlsEnabled: false,
                                      onMapCreated: (controller) {
                                        _previewMapController = controller;
                                        if (_selectedLatLng != null) {
                                          controller.animateCamera(
                                            CameraUpdate.newLatLngZoom(_selectedLatLng!, 16),
                                          );
                                        }
                                      },
                                    ),
                                  // Tap to change overlay
                                  if (_selectedLatLng != null)
                                    Container(
                                      color: Colors.transparent,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.map, color: Colors.white, size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                'Tap to change location',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        
                        Text(
                          'Location Notes / Identification',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add notes to help the rider find your location (e.g., "Blue gate", "Near the church", "2nd floor")',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesController,
                          decoration: InputDecoration(
                            labelText: 'Location notes',
                            hintText: 'Enter location identification or notes',
                            prefixIcon: const Icon(Icons.note),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          maxLines: 3,
                          maxLength: 200,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        
                        Text(
                          'Order Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                ...items.map((item) {
                                  final hasAddons = item.selectedAddons.isNotEmpty;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(bottom: hasAddons ? 8 : 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${item.name} x${item.quantity}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          Text(
                                              '₱${(item.basePriceCents / 100).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Display add-ons
                                      if (hasAddons)
                                        ...item.selectedAddons.map((addon) => Padding(
                                          padding: const EdgeInsets.only(left: 16, bottom: 4),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '+ ${addon.name} x${addon.quantity}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: AppColors.textSecondary,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '₱${(addon.totalCents / 100).toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                      if (hasAddons)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 16, bottom: 8),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Item Total',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              Text(
                                                '₱${(item.lineTotalCents / 100).toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                }),
                                const Divider(),
                                
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Subtotal',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      '₱${(subtotal / 100).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Delivery Fee',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      _deliveryFee != null
                                          ? '₱${_deliveryFee!.toStringAsFixed(2)}'
                                          : 'Calculating...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(),
                                
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      _deliveryFee != null
                                          ? '₱${(total / 100).toStringAsFixed(2)}'
                                          : 'Calculating...',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: ElevatedButton(
                      onPressed: _isPlacingOrder ? null : _placeOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isPlacingOrder
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Place Order',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Map Selector Widget (similar to Padala module)
class _MapSelector extends StatefulWidget {
  final LatLng initialPosition;
  final bool isPickup;
  final Function(LatLng) onLocationSelected;

  const _MapSelector({
    required this.initialPosition,
    required this.isPickup,
    required this.onLocationSelected,
  });

  @override
  State<_MapSelector> createState() => _MapSelectorState();
}

class _MapSelectorState extends State<_MapSelector> {
  late LatLng _selectedPosition;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _selectedPosition,
            zoom: 16,
          ),
          markers: {
            Marker(
              markerId: const MarkerId('selected'),
              position: _selectedPosition,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                widget.isPickup ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
              ),
              draggable: true,
              onDragEnd: (newPosition) {
                setState(() {
                  _selectedPosition = newPosition;
                });
              },
            ),
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: false,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          onMapCreated: (controller) {
            _mapController = controller;
          },
          onTap: (latLng) {
            setState(() {
              _selectedPosition = latLng;
            });
          },
        ),
        // Custom zoom controls
        Positioned(
          top: 100,
          left: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                elevation: 10,
                shadowColor: Colors.black87,
                child: InkWell(
                  onTap: () {
                    if (_mapController != null) {
                      _mapController!.animateCamera(
                        CameraUpdate.zoomIn(),
                      );
                    }
                  },
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      border: Border.all(color: Colors.grey[700]!, width: 2.5),
                    ),
                    child: const Icon(Icons.add, size: 32, color: Colors.black87),
                  ),
                ),
              ),
              Container(
                width: 56,
                height: 2,
                color: Colors.grey[500],
              ),
              Material(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                elevation: 10,
                shadowColor: Colors.black87,
                child: InkWell(
                  onTap: () {
                    if (_mapController != null) {
                      _mapController!.animateCamera(
                        CameraUpdate.zoomOut(),
                      );
                    }
                  },
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      border: Border.all(color: Colors.grey[700]!, width: 2.5),
                    ),
                    child: const Icon(Icons.remove, size: 32, color: Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '💡 Tap anywhere on the map or drag the marker to set location',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  widget.onLocationSelected(_selectedPosition);
                },
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Confirm Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
