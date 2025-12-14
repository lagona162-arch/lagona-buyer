import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/merchant.dart';
import '../models/menu_item.dart';
import '../config/maps_config.dart';

class SupabaseService {
  
  SupabaseClient get _client => Supabase.instance.client;

  
  Future<AuthResponse> signInWithPassword(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? middleInitial,
    DateTime? birthdate,
  }) async {
    
    debugPrint('=== SupabaseService.signUpWithPassword ===');
    debugPrint('Email: $email');
    debugPrint('Password length: ${password.length}');
    debugPrint('First Name: $firstName');
    debugPrint('Last Name: $lastName');
    
    
    final fullName = _constructFullName(firstName, lastName, middleInitial);
    debugPrint('Full Name: $fullName');
    
    try {
      debugPrint('Attempting Supabase auth.signUp...');
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'role': 'customer'},
      );
      
      debugPrint('✅ Auth signUp successful');
      debugPrint('User ID: ${response.user?.id}');
      
      
      final userId = response.user?.id;
      if (userId != null) {
        debugPrint('Creating user record in database...');
        
        
        
        
        
        final passwordHash = _hashPassword(password);
        debugPrint('Password hashed for storage in users table');
        
        final Map<String, dynamic> userData = {
          'id': userId,
          'email': email.trim(),
          'full_name': fullName,
          'firstname': firstName.trim(),
          'lastname': lastName.trim(),
          'role': 'customer',
          'access_status': 'approved', 
          'is_active': true,
          'password': passwordHash, 
        };
        
        
        if (middleInitial != null && middleInitial.trim().isNotEmpty) {
          userData['middle_initial'] = middleInitial.trim().toUpperCase();
        }
        
        if (birthdate != null) {
          userData['birthdate'] = birthdate.toIso8601String().split('T')[0]; 
        }
        
        
        final userDataForLogging = Map<String, dynamic>.from(userData);
        userDataForLogging['password'] = '***HASHED***';
        debugPrint('User data to insert: $userDataForLogging');
        
        try {
          
          debugPrint('Attempting to upsert user data...');
          debugPrint('User data keys: ${userData.keys.toList()}');
          
          await _client.from('users').upsert(userData);
          debugPrint('✅ User record created in users table with hashed password');
        } catch (e, stackTrace) {
          debugPrint('❌ Error creating user record:');
          debugPrint('  Error type: ${e.runtimeType}');
          debugPrint('  Error message: ${e.toString()}');
          debugPrint('  Full error: $e');
          debugPrint('  Stack trace: $stackTrace');
          
          
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('constraint')) {
            debugPrint('⚠️ Database constraint violation detected');
            debugPrint('   This might be a NOT NULL, UNIQUE, or FOREIGN KEY constraint.');
            debugPrint('   Check your database schema for required fields.');
          }
          
          rethrow;
        }
        
        try {
          
          await _client.from('customers').upsert({'id': userId});
          debugPrint('✅ Customer record created');
        } catch (e) {
          debugPrint('❌ Error creating customer record: $e');
          rethrow;
        }
      } else {
        debugPrint('⚠️ Warning: User ID is null after signUp');
      }
      
      debugPrint('=== SignUp Complete ===');
      return response;
    } catch (e, stackTrace) {
      debugPrint('❌ SupabaseService Error:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: ${e.toString()}');
      debugPrint('Full error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      
      if (e.toString().toLowerCase().contains('password')) {
        debugPrint('🔒 Password validation error detected');
      }
      if (e.toString().toLowerCase().contains('email')) {
        debugPrint('📧 Email validation error detected');
      }
      if (e.toString().toLowerCase().contains('constraint')) {
        debugPrint('⚠️ Database constraint error detected');
      }
      
      rethrow;
    }
  }
  
  
  String _constructFullName(String firstName, String lastName, String? middleInitial) {
    final parts = <String>[firstName.trim()];
    if (middleInitial != null && middleInitial.trim().isNotEmpty) {
      parts.add(middleInitial.trim().toUpperCase());
    }
    parts.add(lastName.trim());
    return parts.join(' ');
  }
  
  
  
  
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  
  Future<void> updateCustomerAddress({
    required String customerId,
    required String address,
    required double latitude,
    required double longitude,
    String? phone,
    String? firstName,
    String? lastName,
    String? middleInitial,
  }) async {
    
    final Map<String, dynamic> usersUpdateData = {
      'address': address,
    };
    
    
    if (phone != null && phone.trim().isNotEmpty) {
      usersUpdateData['phone'] = phone.trim();
    }
    
    
    if (firstName != null && firstName.trim().isNotEmpty &&
        lastName != null && lastName.trim().isNotEmpty) {
      usersUpdateData['firstname'] = firstName.trim();
      usersUpdateData['lastname'] = lastName.trim();
      
      if (middleInitial != null && middleInitial.trim().isNotEmpty) {
        usersUpdateData['middle_initial'] = middleInitial.trim().toUpperCase();
      }
      
      
      usersUpdateData['full_name'] = _constructFullName(
        firstName.trim(),
        lastName.trim(),
        middleInitial?.trim(),
      );
    }
    
    
    await _client.from('users').update(usersUpdateData).eq('id', customerId);
    
    
    await _client.from('customers').upsert({
      'id': customerId,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'location_updated_at': DateTime.now().toIso8601String(),
    });
  }

  
  Future<List<Merchant>> getMerchants() async {
    final rows = await _client
        .from('merchants')
        .select('id,business_name,address,latitude,longitude,preview_image,status,access_status')
        .eq('access_status', 'approved');
    
    final merchants = <Merchant>[];
    
    
    for (final row in rows) {
      var address = row['address'] as String?;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      
      
      // Use coordinates format if address is missing
      if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
        if (lat != null && lng != null) {
          address = 'Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        } else {
          address = 'Address not available';
        }
      }
      
      
      final merchantData = Map<String, dynamic>.from(row);
      merchantData['address'] = address;
      
      // Convert preview_image from storage path to public URL if needed
      final previewImage = merchantData['preview_image'] as String?;
      if (previewImage != null && previewImage.isNotEmpty) {
        merchantData['preview_image'] = _convertToPublicUrl(previewImage, 'merchants');
      }
      
      merchants.add(Merchant.fromMap(merchantData));
  }
    
    return merchants;
  }
  

  Future<Merchant?> getMerchantById(String merchantId) async {
    try {
      final row = await _client
          .from('merchants')
          .select('id,business_name,address,latitude,longitude,preview_image,status,access_status')
          .eq('id', merchantId)
          .single();
      
      
      var address = row['address'] as String?;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      
      
      
      // Use coordinates format if address is missing
      if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
        if (lat != null && lng != null) {
          address = 'Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        } else {
          address = 'Address not available';
        }
      }
      
      final merchantData = Map<String, dynamic>.from(row);
      merchantData['address'] = address;
      
      // Convert preview_image from storage path to public URL if needed
      final previewImage = merchantData['preview_image'] as String?;
      if (previewImage != null && previewImage.isNotEmpty) {
        merchantData['preview_image'] = _convertToPublicUrl(previewImage, 'merchants');
      }
      
      return Merchant.fromMap(merchantData);
    } catch (e) {
      debugPrint('Error getting merchant by ID: $e');
      return null;
    }
  }

  
  /// Get distinct categories for a merchant (optimized - only fetches categories)
  Future<List<String>> getMerchantCategories(String merchantId) async {
    try {
      // Fetch only distinct categories
    final rows = await _client
        .from('merchant_products')
          .select('category')
          .eq('merchant_id', merchantId)
          .not('category', 'is', null);

      // Extract unique categories
      final categories = <String>{};
      for (final row in rows) {
        final category = row['category'] as String?;
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }

      // Sort categories alphabetically
      final sortedCategories = categories.toList()..sort();
      return sortedCategories;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching merchant categories:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get products for a merchant filtered by category
  Future<List<MenuItem>> getMerchantProductsByCategory(
    String merchantId,
    String? category,
  ) async {
    try {
      // Build query with conditional category filter
      final queryBuilder = _client
          .from('merchant_products')
          .select('''
            id,
            merchant_id,
            name,
            category,
            price,
            stock,
            image_url,
            product_addons (
              id,
              product_id,
              name,
              price
            )
          ''')
        .eq('merchant_id', merchantId);

      // Filter by category if provided
      final query = (category != null && category.isNotEmpty)
          ? queryBuilder.eq('category', category)
          : queryBuilder;

      try {
        final rows = await query;

        // Extract product IDs
        final productIds = (rows as List).map((e) => e['id'] as String).toList();
        
        // Fetch addons separately for all products
        Map<String, List<dynamic>> addonsMap = {};
        if (productIds.isNotEmpty) {
          try {
            // Build OR query for multiple product_ids
            var addonsQuery = _client.from('product_addons').select('*');
            if (productIds.length == 1) {
              addonsQuery = addonsQuery.eq('product_id', productIds.first);
            } else {
              // Build OR conditions: product_id = id1 OR product_id = id2 OR ...
              final orConditions = productIds
                  .map((id) => 'product_id.eq.$id')
                  .join(',');
              addonsQuery = addonsQuery.or(orConditions);
            }
            
            final allAddons = await addonsQuery;
            
            // Group addons by product_id
            for (final addon in allAddons) {
              final productId = addon['product_id'] as String;
              addonsMap.putIfAbsent(productId, () => []).add(addon);
            }
          } catch (e) {
            // Silently fail - addons will be empty
          }
        }

        final products = (rows as List).map((e) {
          final productData = Map<String, dynamic>.from(e);
          final productId = productData['id'] as String;
          
          // Handle addons - first try from relationship, then from separate query
          dynamic addonsData;
          if (productData.containsKey('product_addons')) {
            addonsData = productData['product_addons'];
          } else if (productData.containsKey('addons')) {
            addonsData = productData['addons'];
          }
          
          List<dynamic> finalAddons = [];
          if (addonsData is List && addonsData.isNotEmpty) {
            finalAddons = addonsData.where((a) => a != null).toList();
          } else if (addonsMap.containsKey(productId)) {
            finalAddons = addonsMap[productId]!;
          }
          
          productData['addons'] = finalAddons;
          
          // Handle optional image_url
          final imageUrl = productData['image_url'] as String?;
          if (imageUrl != null && imageUrl is String && imageUrl.isNotEmpty) {
            productData['photo_url'] = _convertToPublicUrl(imageUrl, 'product-images');
          } else {
            productData['photo_url'] = null;
          }
          
          return MenuItem.fromMap(productData);
        }).toList();

        return products;
      } catch (relationError) {
        debugPrint('⚠️ Relation query failed, trying simple query: $relationError');
        
        // Fallback: Simple query without addons
        final simpleQueryBuilder = _client
        .from('merchant_products')
        .select('id,merchant_id,name,category,price,stock,image_url')
        .eq('merchant_id', merchantId);
        
        final simpleQuery = (category != null && category.isNotEmpty)
            ? simpleQueryBuilder.eq('category', category)
            : simpleQueryBuilder;
        
        final rows = await simpleQuery;
        
        return (rows as List).map((e) {
          final productData = Map<String, dynamic>.from(e);
          productData['addons'] = [];
          
          // Handle optional image_url
          final imageUrl = productData['image_url'] as String?;
          if (imageUrl != null && imageUrl is String && imageUrl.isNotEmpty) {
            productData['photo_url'] = _convertToPublicUrl(imageUrl, 'product-images');
          } else {
            productData['photo_url'] = null;
          }
          
          return MenuItem.fromMap(productData);
        }).toList();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching merchant products by category:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get all products for a merchant (kept for backward compatibility)
  Future<List<MenuItem>> getMerchantProducts(String merchantId) async {
    try {
      // Try fetching products with addons first (if they exist)
      try {
    final rows = await _client
        .from('merchant_products')
            .select('''
              id,
              merchant_id,
              name,
              category,
              price,
              stock,
              image_url,
              product_addons (
                id,
                product_id,
                name,
                price
              )
            ''')
            .eq('merchant_id', merchantId)
            .order('category', ascending: true);

        final products = (rows as List).map((e) {
          final productData = Map<String, dynamic>.from(e);
          
          // Handle addons - some products may not have addons yet
          if (productData['product_addons'] == null) {
            productData['addons'] = [];
            debugPrint('⚠️ No product_addons found for product ${productData['name']}');
          } else {
            // Filter out null addons and ensure we have a list
            final addons = productData['product_addons'];
            if (addons is List) {
              final filteredAddons = addons.where((a) => a != null).toList();
              productData['addons'] = filteredAddons;
              debugPrint('✅ Found ${filteredAddons.length} addons for product ${productData['name']}');
            } else {
              productData['addons'] = [];
              debugPrint('⚠️ product_addons is not a List for product ${productData['name']}');
            }
          }
          
          // Handle optional image_url if it exists (some products may not have photos yet)
          final imageUrl = productData['image_url'] as String?;
          if (imageUrl != null && imageUrl is String && imageUrl.isNotEmpty) {
            productData['photo_url'] = _convertToPublicUrl(imageUrl, 'product-images');
          } else {
            productData['photo_url'] = null;
          }
          
          return MenuItem.fromMap(productData);
        }).toList();

        return products;
      } catch (relationError) {
        debugPrint('⚠️ Relation query failed (products may not have addons yet): $relationError');
        // Fall through to simple query
      }
      
      // Fallback: Simple query without addons for products that don't have them yet
      final rows = await _client
          .from('merchant_products')
          .select('id,merchant_id,name,category,price,stock,image_url')
          .eq('merchant_id', merchantId)
          .order('category', ascending: true);

      return (rows as List).map((e) {
        final productData = Map<String, dynamic>.from(e);
        productData['addons'] = [];
        
        // Handle optional photo_url
        final photoUrl = productData['photo_url'] as String?;
        if (photoUrl != null && photoUrl is String && photoUrl.isNotEmpty) {
          productData['photo_url'] = _convertToPublicUrl(photoUrl, 'product-images');
        } else {
          productData['photo_url'] = null;
        }
        
        return MenuItem.fromMap(productData);
      }).toList();
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching merchant products:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  
  Future<bool> isCustomerProfileComplete(String customerId) async {
    try {
      
      final customerData = await _client
          .from('customers')
          .select('address,latitude,longitude')
          .eq('id', customerId)
          .maybeSingle();
      
      if (customerData == null) return false;
      
      final hasAddress = customerData['address'] != null && 
                         (customerData['address'] as String).trim().isNotEmpty;
      final hasLatitude = customerData['latitude'] != null;
      final hasLongitude = customerData['longitude'] != null;
      
      
      final userData = await _client
          .from('users')
          .select('phone')
          .eq('id', customerId)
          .maybeSingle();
      
      final hasPhone = userData != null && 
                       userData['phone'] != null && 
                       (userData['phone'] as String).trim().isNotEmpty;
      
      
      return hasAddress && hasLatitude && hasLongitude && hasPhone;
    } catch (e) {
      debugPrint('Error checking customer profile completeness: $e');
      return false;
    }
  }

  
  bool _looksLikeCoordinates(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final trimmed = value.trim();
    
    
    final coordPattern = RegExp(r'^-?\d+\.?\d*\s*,\s*-?\d+\.?\d*$');
    final locationAtPattern = RegExp(r'^Location at \d+\.?\d*,\s*\d+\.?\d*$', caseSensitive: false);
    return coordPattern.hasMatch(trimmed) || locationAtPattern.hasMatch(trimmed);
  }
  
  
  Future<String> createOrder({
    required String customerId,
    required String merchantId,
    required List<Map<String, dynamic>> items,
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? deliveryNotes,
    double? deliveryFee,
  }) async {
    try {
      debugPrint('=== Creating Delivery ===');
      debugPrint('Customer ID: $customerId');
      debugPrint('Merchant ID: $merchantId');
      debugPrint('Total Items Count: ${items.length}');
      
      // Log all items with their details
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        debugPrint('📦 Item ${i + 1}:');
        debugPrint('   - Product ID: ${item['menu_item_id']}');
        debugPrint('   - Name: ${item['name']}');
        debugPrint('   - Price (cents): ${item['price_cents']}');
        debugPrint('   - Quantity: ${item['quantity']}');
        final addons = item['addons'] as List<dynamic>? ?? [];
        debugPrint('   - Add-ons Count: ${addons.length}');
        if (addons.isNotEmpty) {
          for (int j = 0; j < addons.length; j++) {
            final addon = addons[j];
            debugPrint('      ➕ Add-on ${j + 1}:');
            debugPrint('         - Addon ID: ${addon['addon_id']}');
            debugPrint('         - Name: ${addon['name']}');
            debugPrint('         - Price (cents): ${addon['price_cents']}');
            debugPrint('         - Quantity: ${addon['quantity']}');
          }
        }
      }

      
      Map<String, dynamic> customerData;
      if (deliveryAddress != null && deliveryLatitude != null && deliveryLongitude != null) {
        
        customerData = {
          'address': deliveryAddress,
          'latitude': deliveryLatitude,
          'longitude': deliveryLongitude,
        };
      } else {
        
        customerData = await _client
          .from('customers')
          .select('address, latitude, longitude')
          .eq('id', customerId)
          .single();
      }

      
      final merchantData = await _client
          .from('merchants')
          .select('address, latitude, longitude')
          .eq('id', merchantId)
          .single();

      final customerAddress = customerData['address'] as String?;
      final merchantAddress = merchantData['address'] as String?;
      final customerLat = customerData['latitude'] as num?;
      final customerLng = customerData['longitude'] as num?;
      final merchantLat = merchantData['latitude'] as num?;
      final merchantLng = merchantData['longitude'] as num?;

      debugPrint('Customer address (raw): $customerAddress');
      debugPrint('Merchant address (raw): $merchantAddress');
      debugPrint('Customer lat/lng: $customerLat, $customerLng');
      debugPrint('Merchant lat/lng: $merchantLat, $merchantLng');

      
      String? pickupAddress = merchantAddress;
      String? dropoffAddress = customerAddress;

      
      // Use coordinates format if addresses are missing
      if ((pickupAddress == null || pickupAddress.isEmpty || pickupAddress.length < 10) &&
          merchantLat != null && merchantLng != null) {
        pickupAddress = 'Location at ${merchantLat.toStringAsFixed(6)}, ${merchantLng.toStringAsFixed(6)}';
      }

      
      if (_looksLikeCoordinates(dropoffAddress) && customerLat != null && customerLng != null) {
        dropoffAddress = 'Location at ${customerLat.toStringAsFixed(6)}, ${customerLng.toStringAsFixed(6)}';
      } else if ((dropoffAddress == null || dropoffAddress.isEmpty) &&
          customerLat != null && customerLng != null) {
        dropoffAddress = 'Location at ${customerLat.toStringAsFixed(6)}, ${customerLng.toStringAsFixed(6)}';
      }

      
      pickupAddress ??= merchantAddress ?? 'Unknown pickup location';
      dropoffAddress ??= customerAddress ?? 'Unknown dropoff location';

      debugPrint('✅ Final pickup address: $pickupAddress');
      debugPrint('✅ Final dropoff address: $dropoffAddress');

      
      
      
      
      final deliveryData = <String, dynamic>{
        'type': 'food', 
        'customer_id': customerId,
        'merchant_id': merchantId,
        'status': 'pending', 
        'pickup_address': pickupAddress,
        'dropoff_address': dropoffAddress,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      
      if (deliveryNotes != null && deliveryNotes.trim().isNotEmpty) {
        deliveryData['delivery_notes'] = deliveryNotes.trim();
      }

      
      if (deliveryFee != null && deliveryFee > 0) {
        deliveryData['delivery_fee'] = deliveryFee;
      }

      
      if (merchantLat != null && merchantLng != null) {
        deliveryData['pickup_latitude'] = merchantLat.toDouble();
        deliveryData['pickup_longitude'] = merchantLng.toDouble();
        debugPrint('Pickup coordinates: ${merchantLat.toDouble()}, ${merchantLng.toDouble()}');
      }

      if (customerLat != null && customerLng != null) {
        deliveryData['dropoff_latitude'] = customerLat.toDouble();
        deliveryData['dropoff_longitude'] = customerLng.toDouble();
        debugPrint('Dropoff coordinates: ${customerLat.toDouble()}, ${customerLng.toDouble()}');
      }

      // Calculate distance for logging (not saved to database)
      if (merchantLat != null && merchantLng != null && customerLat != null && customerLng != null) {
        final distance = _calculateDistance(
          merchantLat.toDouble(),
          merchantLng.toDouble(),
          customerLat.toDouble(),
          customerLng.toDouble(),
        );
        debugPrint('📏 Calculated distance: ${distance.toStringAsFixed(2)} km');
      }

      final deliveryResponse = await _client
          .from('deliveries')
          .insert(deliveryData)
          .select('id')
          .single();

      final deliveryId = deliveryResponse['id'] as String;
      debugPrint('✅ Delivery created with ID: $deliveryId');

      
      // Insert delivery items and get their IDs to link add-ons
      final List<Map<String, dynamic>> deliveryItemsWithIds = [];
      
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final priceCents = item['price_cents'] as int;
        final quantity = item['quantity'] as int;
        final subtotal = priceCents * quantity;
        final addons = item['addons'] as List<dynamic>? ?? [];
        final productName = item['name'] as String? ?? 'Unknown Product';

        debugPrint('💾 Saving Product ${i + 1}: $productName');
        debugPrint('   - Product ID: ${item['menu_item_id']}');
        debugPrint('   - Quantity: $quantity');
        debugPrint('   - Price per unit: ₱${(priceCents / 100).toStringAsFixed(2)}');
        debugPrint('   - Subtotal: ₱${(subtotal / 100).toStringAsFixed(2)}');

        // Insert delivery item and get its ID
        final deliveryItemData = {
          'delivery_id': deliveryId,
          'product_id': item['menu_item_id'],
          'quantity': quantity,
          'subtotal': subtotal / 100.0,
        };
        
        debugPrint('   - Inserting into delivery_items: $deliveryItemData');
        final deliveryItemResponse = await _client
            .from('delivery_items')
            .insert(deliveryItemData)
            .select('id')
            .single();

        final deliveryItemId = deliveryItemResponse['id'] as String;
        debugPrint('   ✅ Product saved! Delivery Item ID: $deliveryItemId');
        
        deliveryItemsWithIds.add({
          'id': deliveryItemId,
          'addons': addons,
        });

        // Insert add-ons for this delivery item if any
        if (addons.isNotEmpty) {
          debugPrint('   📝 Saving ${addons.length} add-on(s) for $productName:');
          
          final deliveryItemAddons = addons.map<Map<String, dynamic>>((addon) {
            final addonPriceCents = addon['price_cents'] as int;
            final addonQuantity = addon['quantity'] as int;
            final addonSubtotal = addonPriceCents * addonQuantity;
            final addonName = addon['name'] as String? ?? 'Unknown Addon';

            debugPrint('      ➕ Add-on: $addonName');
            debugPrint('         - Addon ID: ${addon['addon_id']}');
            debugPrint('         - Quantity: $addonQuantity');
            debugPrint('         - Price per unit: ₱${(addonPriceCents / 100).toStringAsFixed(2)}');
            debugPrint('         - Subtotal: ₱${(addonSubtotal / 100).toStringAsFixed(2)}');

            return {
              'delivery_item_id': deliveryItemId,
              'addon_id': addon['addon_id'],
              'name': addonName,
              'price': addonPriceCents / 100.0,
              'quantity': addonQuantity,
              'subtotal': addonSubtotal / 100.0,
            };
          }).toList();

          debugPrint('   - Inserting ${deliveryItemAddons.length} add-on(s) into delivery_item_addons');
          await _client.from('delivery_item_addons').insert(deliveryItemAddons);
          debugPrint('   ✅ All ${deliveryItemAddons.length} add-on(s) saved successfully for $productName');
        } else {
          debugPrint('   ℹ️  No add-ons for $productName');
        }
      }

      debugPrint('✅ All delivery items created: ${deliveryItemsWithIds.length}');
      
      // Final summary
      int totalAddonsCount = 0;
      for (final itemWithId in deliveryItemsWithIds) {
        final addons = itemWithId['addons'] as List<dynamic>? ?? [];
        totalAddonsCount += addons.length;
      }
      
      debugPrint('📊 Order Summary:');
      debugPrint('   - Total Products: ${deliveryItemsWithIds.length}');
      debugPrint('   - Total Add-ons: $totalAddonsCount');
      debugPrint('   - Delivery ID: $deliveryId');

      debugPrint('=== ✅ Delivery Creation Complete ===');
      return deliveryId;
    } catch (e, stackTrace) {
      debugPrint('❌ Error creating delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  
  Future<List<Map<String, dynamic>>> findNearbyRiders({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    try {
      debugPrint('=== Finding Nearby Riders ===');
      debugPrint('Location: $latitude, $longitude');
      debugPrint('Radius: $radiusKm km');

      
      
      
      final riders = await _client
          .from('riders')
          .select('id, latitude, longitude, status, last_active')
          .eq('status', 'available')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);

      debugPrint('Found ${riders.length} available riders');

      
      final now = DateTime.now();
      final recentRiders = <Map<String, dynamic>>[];

      for (final rider in riders) {
        final riderLat = rider['latitude'] as double?;
        final riderLng = rider['longitude'] as double?;
        final lastActive = rider['last_active'] as String?;

        if (riderLat == null || riderLng == null) continue;

        
        if (lastActive != null) {
          final lastActiveTime = DateTime.parse(lastActive);
          final timeSinceActive = now.difference(lastActiveTime);
          if (timeSinceActive.inMinutes > 15) {
            continue; 
          }
        }

        
        final distance = _calculateDistance(latitude, longitude, riderLat, riderLng);
        
        if (distance <= radiusKm) {
          recentRiders.add({
            'id': rider['id'],
            'latitude': riderLat,
            'longitude': riderLng,
            'distance': distance,
          });
        }
      }

      
      recentRiders.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      debugPrint('Found ${recentRiders.length} nearby active riders');
      return recentRiders;
    } catch (e, stackTrace) {
      debugPrint('❌ Error finding nearby riders:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0; 
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  /// Convert storage path to public URL, or return as-is if already a full URL
  /// 
  /// If the path is already a full URL (starts with http/https), returns it unchanged.
  /// Otherwise, converts the storage path to a public URL using Supabase Storage.
  String _convertToPublicUrl(String pathOrUrl, String bucketName) {
    // If it's already a full URL, return as-is
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    
    // Remove leading slash if present
    final cleanPath = pathOrUrl.startsWith('/') ? pathOrUrl.substring(1) : pathOrUrl;
    
    // Convert storage path to public URL using Supabase Storage
    // getPublicUrl constructs the URL - it doesn't verify file existence
    try {
      final publicUrl = _client.storage.from(bucketName).getPublicUrl(cleanPath);
      return publicUrl;
    } catch (e) {
      debugPrint('⚠️ Error converting storage path to public URL: $pathOrUrl');
      debugPrint('   Bucket: $bucketName, Error: $e');
      // Return the original path if conversion fails
      return pathOrUrl;
    }
  }

  
  Future<void> assignRiderToDelivery({
    required String deliveryId,
    required String riderId,
  }) async {
    try {
      debugPrint('=== Assigning Rider to Delivery ===');
      debugPrint('Delivery ID: $deliveryId');
      debugPrint('Rider ID: $riderId');

      await _client
          .from('deliveries')
          .update({
            'rider_id': riderId,
            'status': 'accepted',
          })
          .eq('id', deliveryId);

      debugPrint('✅ Rider assigned to delivery');
    } catch (e, stackTrace) {
      debugPrint('❌ Error assigning rider to delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  
  Future<Map<String, dynamic>?> getDeliveryById(String deliveryId) async {
    try {
      debugPrint('=== Fetching Delivery Details ===');
      debugPrint('Delivery ID: $deliveryId');

      
      final delivery = await _client
          .from('deliveries')
          .select('''
            *,
            delivery_items (
              id,
              quantity,
              subtotal,
              merchant_products:product_id (
                id,
                name,
                price
              ),
              delivery_item_addons (
                id,
                addon_id,
                name,
                price,
                quantity,
                subtotal
              )
            )
          ''')
          .eq('id', deliveryId)
          .maybeSingle();
      
      

      if (delivery == null) {
        debugPrint('⚠️ Delivery not found');
        return null;
      }

      debugPrint('✅ Delivery fetched');
      debugPrint('Status: ${delivery['status']}');
      debugPrint('Rider ID: ${delivery['rider_id']}');

      
      final riderId = delivery['rider_id'] as String?;
      if (riderId != null) {
        try {
          final rider = await _client
              .from('riders')
              .select('id, latitude, longitude, current_address, last_active, status')
              .eq('id', riderId)
              .maybeSingle();

          if (rider != null) {
            delivery['riders'] = rider;
            debugPrint('Rider location: ${rider['latitude']}, ${rider['longitude']}');
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching rider details: $e');
        }
      }

      
      final merchantId = delivery['merchant_id'] as String?;
      if (merchantId != null) {
        try {
          final merchant = await _client
              .from('merchants')
              .select('gcash_qr_url, gcash_number')
              .eq('id', merchantId)
              .maybeSingle();

          if (merchant != null) {
            delivery['merchant_gcash_qr_url'] = merchant['gcash_qr_url'];
            delivery['merchant_gcash_number'] = merchant['gcash_number'];
            
            
            if (merchant['gcash_number'] == null) {
              final merchantUser = await _client
                  .from('users')
                  .select('phone')
                  .eq('id', merchantId)
                  .maybeSingle();
              
              if (merchantUser != null) {
                delivery['merchant_gcash_number'] = merchantUser['phone'];
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching merchant GCash info: $e');
        }
      }

      
      if (delivery['pickup_photo_url'] != null) {
        delivery['pickup_image'] = delivery['pickup_photo_url'];
      }
      if (delivery['dropoff_photo_url'] != null) {
        delivery['dropoff_image'] = delivery['dropoff_photo_url'];
      }

      return delivery;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  
  Future<Map<String, dynamic>?> getCustomerLocation(String customerId) async {
    try {
      final customer = await _client
          .from('customers')
          .select('id, latitude, longitude, address')
          .eq('id', customerId)
          .maybeSingle();
      return customer;
    } catch (e) {
      debugPrint('Error fetching customer location: $e');
      return null;
    }
  }

  
  Future<List<Map<String, dynamic>>> getCustomerDeliveries({
    required String customerId,
    String? status,
  }) async {
    try {
      var query = _client
          .from('deliveries')
          .select('''
            *,
            merchants:merchant_id (
              id,
              business_name,
              address,
              preview_image
            ),
            delivery_items (
              id,
              quantity,
              subtotal,
              merchant_products:product_id (
                id,
                name,
                price
              ),
              delivery_item_addons (
                id,
                addon_id,
                name,
                price,
                quantity,
                subtotal
              )
            )
          ''')
          .eq('customer_id', customerId);

      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }

      final deliveries = await query.order('created_at', ascending: false);
      
      final mappedDeliveries = deliveries.map<Map<String, dynamic>>((delivery) {
        final deliveryMap = Map<String, dynamic>.from(delivery);
        if (deliveryMap['pickup_photo_url'] != null) {
          deliveryMap['pickup_image'] = deliveryMap['pickup_photo_url'];
        }
        if (deliveryMap['dropoff_photo_url'] != null) {
          deliveryMap['dropoff_image'] = deliveryMap['dropoff_photo_url'];
        }
        return deliveryMap;
      }).toList();
      
      return mappedDeliveries;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching customer deliveries:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  
  Future<void> completeDelivery({
    required String deliveryId,
    required String customerId,
  }) async {
    try {
      debugPrint('=== Completing Delivery ===');
      debugPrint('Delivery ID: $deliveryId');
      debugPrint('Customer ID: $customerId');

      
      final delivery = await _client
          .from('deliveries')
          .select('id, customer_id, status')
          .eq('id', deliveryId)
          .single();

      if (delivery['customer_id'] != customerId) {
        throw Exception('Delivery does not belong to this customer');
      }

      final currentStatus = delivery['status']?.toString().toLowerCase() ?? '';
      
      
      
      if (currentStatus != 'delivered') {
        throw Exception('Delivery must be delivered before it can be marked as completed');
      }

      
      await _client
          .from('deliveries')
          .update({'status': 'completed'})
          .eq('id', deliveryId);

      debugPrint('✅ Delivery marked as completed');
    } catch (e, stackTrace) {
      debugPrint('❌ Error completing delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  
  Future<void> submitPayment({
    required String deliveryId,
    required String customerId,
    required File paymentImage,
    required String referenceNumber,
    required double amount,
    required String senderName,
  }) async {
    try {
      debugPrint('=== Submitting Payment ===');
      debugPrint('Delivery ID: $deliveryId');
      debugPrint('Customer ID: $customerId');
      debugPrint('Reference Number: $referenceNumber');
      debugPrint('Amount: $amount');
      debugPrint('Sender Name: $senderName');

      
      final user = _client.auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to submit payment');
      }
      debugPrint('✅ User authenticated: ${user.id}');
      
      
      final authenticatedUserId = user.id;
      if (authenticatedUserId != customerId) {
        debugPrint('⚠️ Warning: customerId ($customerId) does not match authenticated user ID ($authenticatedUserId)');
      }

      
      final delivery = await _client
          .from('deliveries')
          .select('id, customer_id, status')
          .eq('id', deliveryId)
          .single();

      if (delivery['customer_id'] != customerId) {
        throw Exception('Delivery does not belong to this customer');
      }

      
      
      
      
      final session = _client.auth.currentSession;
      if (session == null) {
        throw Exception('No active session. Please log in again.');
      }
      debugPrint('✅ User authenticated: $authenticatedUserId');
      debugPrint('✅ Session exists: ${session.accessToken != null}');
      
      
      
      
      final filePath = '${authenticatedUserId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final fileBytes = await paymentImage.readAsBytes();

      debugPrint('=== Storage Upload Debug ===');
      debugPrint('User ID: $authenticatedUserId');
      debugPrint('File path: $filePath');
      debugPrint('File size: ${fileBytes.length} bytes');
      debugPrint('Bucket: payment-proofs');
      debugPrint('Expected folder (first part): ${filePath.split('/')[0]}');
      
      String imageUrl;
      try {
        
        
        
        debugPrint('Attempting upload...');
      await _client.storage
          .from('payment-proofs')
          .uploadBinary(
              filePath,
              fileBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
        debugPrint('✅ Upload successful!');

        debugPrint('✅ Payment image uploaded successfully');

      
        imageUrl = _client.storage
          .from('payment-proofs')
            .getPublicUrl(filePath);
      } catch (storageError) {
        debugPrint('❌ Storage upload error: $storageError');
        debugPrint('❌ Error details: ${storageError.toString()}');
        debugPrint('❌ File path attempted: $filePath');
        debugPrint('❌ User ID: $authenticatedUserId');
        debugPrint('❌ First folder in path: ${filePath.split('/')[0]}');
        
        
        
        throw Exception(
          'Failed to upload payment image: ${storageError.toString()}. '
          'Please try again or contact support.'
        );
      }

      debugPrint('✅ Payment image uploaded: $imageUrl');

      
      
      await _client.from('payments').insert({
        'delivery_id': deliveryId,
        'customer_id': customerId,
        'payment_proof_url': imageUrl,
        'reference_number': referenceNumber,
        'amount': amount,
        'ewallet_name': senderName, 
        'status': 'pending',
        
      });
      debugPrint('✅ Payment record created in payments table');

      debugPrint('✅ Payment submitted successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Error submitting payment:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // ============ PADALA (PARCEL DELIVERY) METHODS ============
  
  /// Create a new Padala (parcel delivery) booking
  Future<String> createPadalaBooking({
    required String customerId,
    required String pickupAddress,
    required double pickupLatitude,
    required double pickupLongitude,
    required String senderName,
    required String senderPhone,
    String? senderNotes,
    required String dropoffAddress,
    required double dropoffLatitude,
    required double dropoffLongitude,
    required String recipientName,
    required String recipientPhone,
    String? recipientNotes,
    String? packageDescription,
    double? deliveryFee,
  }) async {
    try {
      debugPrint('=== Creating Padala Booking ===');
      debugPrint('Customer ID: $customerId');
      debugPrint('Pickup: $pickupAddress');
      debugPrint('Dropoff: $dropoffAddress');

      // Create Padala details object to store in delivery_notes as JSON
      final padalaDetails = {
        'sender_name': senderName,
        'sender_phone': senderPhone,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
      };

      if (senderNotes != null && senderNotes.trim().isNotEmpty) {
        padalaDetails['sender_notes'] = senderNotes.trim();
      }

      if (recipientNotes != null && recipientNotes.trim().isNotEmpty) {
        padalaDetails['recipient_notes'] = recipientNotes.trim();
      }

      if (packageDescription != null && packageDescription.trim().isNotEmpty) {
        padalaDetails['package_description'] = packageDescription.trim();
      }

      final padalaData = <String, dynamic>{
        'type': 'parcel',
        'customer_id': customerId,
        'status': 'pending',
        'pickup_address': pickupAddress,
        'pickup_latitude': pickupLatitude,
        'pickup_longitude': pickupLongitude,
        'dropoff_address': dropoffAddress,
        'dropoff_latitude': dropoffLatitude,
        'dropoff_longitude': dropoffLongitude,
        'delivery_notes': jsonEncode(padalaDetails), // Store Padala details as JSON
        'created_at': DateTime.now().toIso8601String(),
      };

      if (deliveryFee != null && deliveryFee > 0) {
        padalaData['delivery_fee'] = deliveryFee;
      }

      // Calculate distance for logging (not saved to database)
      final distance = _calculateDistance(
        pickupLatitude,
        pickupLongitude,
        dropoffLatitude,
        dropoffLongitude,
      );
      debugPrint('📏 Calculated Padala distance: ${distance.toStringAsFixed(2)} km');

      final padalaResponse = await _client
          .from('deliveries')
          .insert(padalaData)
          .select('id')
          .single();

      final padalaId = padalaResponse['id'] as String;
      debugPrint('✅ Padala booking created with ID: $padalaId');

      return padalaId;
    } catch (e, stackTrace) {
      debugPrint('❌ Error creating Padala booking:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Get Padala delivery details by ID
  Future<Map<String, dynamic>?> getPadalaById(String padalaId) async {
    try {
      debugPrint('=== Fetching Padala Details ===');
      debugPrint('Padala ID: $padalaId');

      final padala = await _client
          .from('deliveries')
          .select('*')
          .eq('id', padalaId)
          .eq('type', 'parcel')
          .maybeSingle();

      if (padala == null) {
        debugPrint('⚠️ Padala not found');
        return null;
      }

      // Parse Padala details from delivery_notes JSON
      final deliveryNotes = padala['delivery_notes'] as String?;
      if (deliveryNotes != null && deliveryNotes.isNotEmpty) {
        try {
          final padalaDetails = jsonDecode(deliveryNotes) as Map<String, dynamic>;
          // Merge padala details into the main object
          padala.addAll(padalaDetails);
        } catch (e) {
          debugPrint('⚠️ Error parsing Padala details from delivery_notes: $e');
        }
      }

      debugPrint('✅ Padala fetched');
      debugPrint('Status: ${padala['status']}');
      debugPrint('Rider ID: ${padala['rider_id']}');

      // Fetch rider location if rider is assigned
      final riderId = padala['rider_id'] as String?;
      if (riderId != null) {
        try {
          final rider = await _client
              .from('riders')
              .select('id, latitude, longitude, current_address, last_active, status')
              .eq('id', riderId)
              .maybeSingle();

          if (rider != null) {
            padala['riders'] = rider;
            debugPrint('Rider location: ${rider['latitude']}, ${rider['longitude']}');
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching rider details: $e');
        }
      }

      return padala;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching Padala:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get all Padala deliveries for a customer
  Future<List<Map<String, dynamic>>> getCustomerPadalaDeliveries({
    required String customerId,
    String? status,
  }) async {
    try {
      debugPrint('=== Fetching Customer Padala Deliveries ===');
      debugPrint('Customer ID: $customerId');
      debugPrint('Status filter: ${status ?? 'all'}');

      var query = _client
          .from('deliveries')
          .select('*')
          .eq('customer_id', customerId)
          .eq('type', 'parcel');

      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }

      final padalaDeliveries = await query.order('created_at', ascending: false);

      debugPrint('✅ Found ${padalaDeliveries.length} Padala deliveries');
      return padalaDeliveries;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching customer Padala deliveries:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Assign rider to Padala delivery
  Future<void> assignRiderToPadala({
    required String padalaId,
    required String riderId,
  }) async {
    try {
      debugPrint('=== Assigning Rider to Padala ===');
      debugPrint('Padala ID: $padalaId');
      debugPrint('Rider ID: $riderId');

      await _client
          .from('deliveries')
          .update({
            'rider_id': riderId,
            'status': 'accepted',
          })
          .eq('id', padalaId)
          .eq('type', 'parcel');

      debugPrint('✅ Rider assigned to Padala');
    } catch (e, stackTrace) {
      debugPrint('❌ Error assigning rider to Padala:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Cancel a delivery (works for both food and Padala)
  Future<void> cancelDelivery({
    required String deliveryId,
    required String customerId,
  }) async {
    try {
      debugPrint('=== Cancelling Delivery ===');
      debugPrint('Delivery ID: $deliveryId');
      debugPrint('Customer ID: $customerId');

      // Verify delivery belongs to customer
      final delivery = await _client
          .from('deliveries')
          .select('id, customer_id, status')
          .eq('id', deliveryId)
          .single();

      if (delivery['customer_id'] != customerId) {
        throw Exception('Delivery does not belong to this customer');
      }

      final currentStatus = delivery['status']?.toString().toLowerCase() ?? '';
      
      // Only allow cancellation if not already delivered or completed
      if (currentStatus == 'delivered' || currentStatus == 'completed') {
        throw Exception('Cannot cancel a delivery that has already been delivered or completed');
      }

      if (currentStatus == 'cancelled') {
        throw Exception('Delivery is already cancelled');
      }

      // Update delivery status to cancelled
      await _client
          .from('deliveries')
          .update({'status': 'cancelled'})
          .eq('id', deliveryId);

      debugPrint('✅ Delivery cancelled successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Error cancelling delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
}



