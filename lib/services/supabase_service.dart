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
  // Get client lazily to ensure Supabase is initialized first
  SupabaseClient get _client => Supabase.instance.client;

  // Auth
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
    // Debug logging
    debugPrint('=== SupabaseService.signUpWithPassword ===');
    debugPrint('Email: $email');
    debugPrint('Password length: ${password.length}');
    debugPrint('First Name: $firstName');
    debugPrint('Last Name: $lastName');
    
    // Construct full name from parts
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
      
      // Create row in users table with all required fields
      final userId = response.user?.id;
      if (userId != null) {
        debugPrint('Creating user record in database...');
        
        // Prepare user data
        // Hash the password for storage in public.users table
        // Note: The actual password is securely stored in auth.users by Supabase Auth
        // This hash is stored in public.users to satisfy the NOT NULL constraint
        final passwordHash = _hashPassword(password);
        debugPrint('Password hashed for storage in users table');
        
        final Map<String, dynamic> userData = {
          'id': userId,
          'email': email.trim(),
          'full_name': fullName,
          'firstname': firstName.trim(),
          'lastname': lastName.trim(),
          'role': 'customer',
          'access_status': 'approved', // Customers are auto-approved
          'is_active': true,
          'password': passwordHash, // Hashed password for database storage
        };
        
        // Add optional fields
        if (middleInitial != null && middleInitial.trim().isNotEmpty) {
          userData['middle_initial'] = middleInitial.trim().toUpperCase();
        }
        
        if (birthdate != null) {
          userData['birthdate'] = birthdate.toIso8601String().split('T')[0]; // Format as YYYY-MM-DD
        }
        
        // Don't log password hash for security
        final userDataForLogging = Map<String, dynamic>.from(userData);
        userDataForLogging['password'] = '***HASHED***';
        debugPrint('User data to insert: $userDataForLogging');
        
        try {
          // Insert into users table with all fields (including hashed password)
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
          
          // Check for specific database constraint errors
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('constraint')) {
            debugPrint('⚠️ Database constraint violation detected');
            debugPrint('   This might be a NOT NULL, UNIQUE, or FOREIGN KEY constraint.');
            debugPrint('   Check your database schema for required fields.');
          }
          
          rethrow;
        }
        
        try {
          // Create row in customers table
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
      
      // Check for specific error types
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
  
  /// Constructs full name from firstname, lastname, and optional middle initial
  String _constructFullName(String firstName, String lastName, String? middleInitial) {
    final parts = <String>[firstName.trim()];
    if (middleInitial != null && middleInitial.trim().isNotEmpty) {
      parts.add(middleInitial.trim().toUpperCase());
    }
    parts.add(lastName.trim());
    return parts.join(' ');
  }
  
  /// Hashes a password using SHA-256
  /// Note: This is for storing in public.users table to satisfy NOT NULL constraint.
  /// The actual secure password hash is managed by Supabase Auth in auth.users.
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // Customers address update after registration
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
    // Prepare users table update data
    final Map<String, dynamic> usersUpdateData = {
      'address': address,
    };
    
    // Add phone if provided
    if (phone != null && phone.trim().isNotEmpty) {
      usersUpdateData['phone'] = phone.trim();
    }
    
    // If name fields are provided, update them
    if (firstName != null && firstName.trim().isNotEmpty &&
        lastName != null && lastName.trim().isNotEmpty) {
      usersUpdateData['firstname'] = firstName.trim();
      usersUpdateData['lastname'] = lastName.trim();
      
      if (middleInitial != null && middleInitial.trim().isNotEmpty) {
        usersUpdateData['middle_initial'] = middleInitial.trim().toUpperCase();
      }
      
      // Reconstruct full name
      usersUpdateData['full_name'] = _constructFullName(
        firstName.trim(),
        lastName.trim(),
        middleInitial?.trim(),
      );
    }
    
    // Update users table with address, phone, and name if provided
    await _client.from('users').update(usersUpdateData).eq('id', customerId);
    
    // Update customers table with address and location
    await _client.from('customers').upsert({
      'id': customerId,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'location_updated_at': DateTime.now().toIso8601String(),
    });
  }

  // Merchants
  Future<List<Merchant>> getMerchants() async {
    final rows = await _client
        .from('merchants')
        .select('id,business_name,address,latitude,longitude,preview_image,status,access_status')
        .eq('access_status', 'approved');
    
    final merchants = <Merchant>[];
    
    // Process each merchant and reverse geocode coordinates if needed
    for (final row in rows) {
      var address = row['address'] as String?;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      
      // Always try to reverse geocode if we have coordinates
      if (lat != null && lng != null) {
        // If address looks like coordinates or is missing, definitely reverse geocode
        if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
          try {
            final geocodedAddress = await _reverseGeocode(lat, lng);
            if (geocodedAddress != null && geocodedAddress.isNotEmpty) {
              address = geocodedAddress;
            }
          } catch (e) {
            debugPrint('Error reverse geocoding merchant address: $e');
          }
        }
        
        // If address is still null or looks like coordinates after reverse geocoding
        if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
          // Try one more time with a simpler reverse geocode request
          try {
            final simpleAddress = await _reverseGeocodeSimple(lat, lng);
            if (simpleAddress != null && simpleAddress.isNotEmpty) {
              address = simpleAddress;
            }
          } catch (e) {
            debugPrint('Error in simple reverse geocoding: $e');
          }
        }
      }
      
      // Final fallback - only use coordinates if absolutely necessary
      if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
        if (lat != null && lng != null) {
          address = 'Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        } else {
          address = 'Address not available';
        }
      }
      
      // Update the address in the row
      final merchantData = Map<String, dynamic>.from(row);
      merchantData['address'] = address;
      
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
      
      // Process address similar to getMerchants
      var address = row['address'] as String?;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      
      // Always try to reverse geocode if we have coordinates, even if address exists
      // This ensures we get the most up-to-date and readable address
      if (lat != null && lng != null) {
        // If address looks like coordinates or is missing, definitely reverse geocode
        if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
          try {
            final geocodedAddress = await _reverseGeocode(lat, lng);
            if (geocodedAddress != null && geocodedAddress.isNotEmpty) {
              address = geocodedAddress;
            }
          } catch (e) {
            debugPrint('Error reverse geocoding merchant address: $e');
          }
        }
        
        // If address is still null or looks like coordinates after reverse geocoding
        if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
          // Try one more time with a simpler reverse geocode request
          try {
            final simpleAddress = await _reverseGeocodeSimple(lat, lng);
            if (simpleAddress != null && simpleAddress.isNotEmpty) {
              address = simpleAddress;
            }
          } catch (e) {
            debugPrint('Error in simple reverse geocoding: $e');
          }
        }
      }
      
      // Final fallback - only use coordinates if absolutely necessary
      if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
        if (lat != null && lng != null) {
          // Try to extract at least a city name from coordinates
          address = 'Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        } else {
          address = 'Address not available';
        }
      }
      
      final merchantData = Map<String, dynamic>.from(row);
      merchantData['address'] = address;
      
      return Merchant.fromMap(merchantData);
    } catch (e) {
      debugPrint('Error getting merchant by ID: $e');
      return null;
    }
  }

  // Products for a merchant
  Future<List<MenuItem>> getMerchantProducts(String merchantId) async {
    final rows = await _client
        .from('merchant_products')
        .select('id,merchant_id,name,category,price,stock')
        .eq('merchant_id', merchantId);
    return (rows as List).map((e) => MenuItem.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  // Check if customer profile is complete
  Future<bool> isCustomerProfileComplete(String customerId) async {
    try {
      // Check customers table for address and location
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
      
      // Also check users table for phone
      final userData = await _client
          .from('users')
          .select('phone')
          .eq('id', customerId)
          .maybeSingle();
      
      final hasPhone = userData != null && 
                       userData['phone'] != null && 
                       (userData['phone'] as String).trim().isNotEmpty;
      
      // Profile is complete if address, location (lat/long), and phone are all set
      return hasAddress && hasLatitude && hasLongitude && hasPhone;
    } catch (e) {
      debugPrint('Error checking customer profile completeness: $e');
      return false;
    }
  }

  // Reverse geocode coordinates to get address
  Future<String?> _reverseGeocode(double latitude, double longitude) async {
    try {
      final apiKey = MapsConfig.apiKey;
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '$latitude,$longitude',
          'key': apiKey,
          'result_type': 'street_address|premise|route|sublocality|locality|administrative_area_level_1',
          'language': 'en',
        },
      );

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          // Try to get a shorter, more readable address
          // Prefer formatted address, but try to extract city/landmark if available
          final formattedAddress = results.first['formatted_address'] as String?;
          
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            // Extract a shorter address (remove country if it makes it too long)
            String address = formattedAddress;
            
            // Try to get address components for better formatting
            final addressComponents = results.first['address_components'] as List?;
            if (addressComponents != null) {
              String? locality;
              String? sublocality;
              String? route;
              String? streetNumber;
              String? administrativeAreaLevel1;
              
              for (final component in addressComponents) {
                final types = component['types'] as List?;
                if (types != null) {
                  if (types.contains('locality')) {
                    locality = component['long_name'] as String?;
                  } else if (types.contains('sublocality') || types.contains('sublocality_level_1')) {
                    sublocality = component['long_name'] as String?;
                  } else if (types.contains('route')) {
                    route = component['long_name'] as String?;
                  } else if (types.contains('street_number')) {
                    streetNumber = component['long_name'] as String?;
                  } else if (types.contains('administrative_area_level_1')) {
                    administrativeAreaLevel1 = component['short_name'] as String?;
                  }
                }
              }
              
              // Build a shorter, more readable address
              final addressParts = <String>[];
              if (streetNumber != null && route != null) {
                addressParts.add('$streetNumber $route');
              } else if (route != null) {
                addressParts.add(route);
              }
              
              if (sublocality != null) {
                addressParts.add(sublocality);
              } else if (locality != null) {
                addressParts.add(locality);
              }
              
              if (administrativeAreaLevel1 != null && addressParts.isNotEmpty) {
                // Use shorter version with city/region
                address = addressParts.join(', ');
                if (administrativeAreaLevel1.isNotEmpty) {
                  address += ', $administrativeAreaLevel1';
                }
              } else if (addressParts.isNotEmpty) {
                address = addressParts.join(', ');
              }
            }
            
            debugPrint('✅ Reverse geocoded: $latitude,$longitude -> $address');
            return address;
          }
        }
      }
      debugPrint('⚠️ Reverse geocoding failed or no results for $latitude,$longitude');
      return null;
    } catch (e) {
      debugPrint('❌ Error in reverse geocoding: $e');
      return null;
    }
  }

  // Check if a string looks like coordinates (e.g., "14.746190, 121.035662" or "Location at 14.746190, 121.035662")
  bool _looksLikeCoordinates(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final trimmed = value.trim();
    // Pattern: numbers with decimal points separated by comma and optional spaces
    // Also check for "Location at" prefix with coordinates
    final coordPattern = RegExp(r'^-?\d+\.?\d*\s*,\s*-?\d+\.?\d*$');
    final locationAtPattern = RegExp(r'^Location at \d+\.?\d*,\s*\d+\.?\d*$', caseSensitive: false);
    return coordPattern.hasMatch(trimmed) || locationAtPattern.hasMatch(trimmed);
  }
  
  // Simple reverse geocode that tries to get at least a city/landmark name
  Future<String?> _reverseGeocodeSimple(double latitude, double longitude) async {
    try {
      final apiKey = MapsConfig.apiKey;
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '$latitude,$longitude',
          'key': apiKey,
          'result_type': 'locality|sublocality|neighborhood|route|premise',
          'language': 'en',
        },
      );

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          // Get the first result which should be the most specific
          final formattedAddress = results.first['formatted_address'] as String?;
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            // Extract just the city/area name (first part before comma usually)
            final parts = formattedAddress.split(',');
            if (parts.isNotEmpty) {
              return parts.first.trim();
            }
            return formattedAddress;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error in simple reverse geocoding: $e');
      return null;
    }
  }

  // Create a delivery (order)
  Future<String> createOrder({
    required String customerId,
    required String merchantId,
    required List<Map<String, dynamic>> items,
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? deliveryNotes,
  }) async {
    try {
      debugPrint('=== Creating Delivery ===');
      debugPrint('Customer ID: $customerId');
      debugPrint('Merchant ID: $merchantId');
      debugPrint('Items: ${items.length}');

      // Fetch customer location and address (use provided values if available)
      Map<String, dynamic> customerData;
      if (deliveryAddress != null && deliveryLatitude != null && deliveryLongitude != null) {
        // Use provided delivery address and coordinates
        customerData = {
          'address': deliveryAddress,
          'latitude': deliveryLatitude,
          'longitude': deliveryLongitude,
        };
      } else {
        // Fetch from database
        customerData = await _client
          .from('customers')
          .select('address, latitude, longitude')
          .eq('id', customerId)
          .single();
      }

      // Fetch merchant location and address
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

      // Get proper addresses using reverse geocoding if needed
      String? pickupAddress = merchantAddress;
      String? dropoffAddress = customerAddress;

      // If merchant address is missing or too vague, use reverse geocoding
      if ((pickupAddress == null || pickupAddress.isEmpty || pickupAddress.length < 10) &&
          merchantLat != null && merchantLng != null) {
        debugPrint('Merchant address is missing or vague, using reverse geocoding...');
        pickupAddress = await _reverseGeocode(
          merchantLat.toDouble(),
          merchantLng.toDouble(),
        );
        // Fallback to stored address if reverse geocoding fails
        pickupAddress ??= merchantAddress ?? 'Unknown location';
      }

      // If customer address looks like coordinates, use reverse geocoding
      if (_looksLikeCoordinates(dropoffAddress) && customerLat != null && customerLng != null) {
        debugPrint('Customer address appears to be coordinates, using reverse geocoding...');
        dropoffAddress = await _reverseGeocode(
          customerLat.toDouble(),
          customerLng.toDouble(),
        );
        // Fallback: if reverse geocoding fails, try to parse and use the coordinates as is
        if (dropoffAddress == null) {
          dropoffAddress = 'Location at ${customerLat.toStringAsFixed(6)}, ${customerLng.toStringAsFixed(6)}';
        }
      } else if ((dropoffAddress == null || dropoffAddress.isEmpty) &&
          customerLat != null && customerLng != null) {
        debugPrint('Customer address is missing, using reverse geocoding...');
        dropoffAddress = await _reverseGeocode(
          customerLat.toDouble(),
          customerLng.toDouble(),
        );
        // Fallback
        dropoffAddress ??= 'Location at ${customerLat.toStringAsFixed(6)}, ${customerLng.toStringAsFixed(6)}';
      }

      // Ensure we have addresses
      pickupAddress ??= merchantAddress ?? 'Unknown pickup location';
      dropoffAddress ??= customerAddress ?? 'Unknown dropoff location';

      debugPrint('✅ Final pickup address: $pickupAddress');
      debugPrint('✅ Final dropoff address: $dropoffAddress');

      // Create delivery record
      // Note: 'type' and 'status' are USER-DEFINED enums in the database
      // If 'food' is not a valid delivery type enum value, adjust accordingly
      // Common values might be: 'food', 'padala', 'parcel', etc.
      final deliveryData = <String, dynamic>{
        'type': 'food', // USER-DEFINED enum - adjust if 'food' is not valid
        'customer_id': customerId,
        'merchant_id': merchantId,
        'status': 'pending', // USER-DEFINED enum - default from schema is 'pending'::delivery_status
        'pickup_address': pickupAddress,
        'dropoff_address': dropoffAddress,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // Add delivery notes if provided
      if (deliveryNotes != null && deliveryNotes.trim().isNotEmpty) {
        deliveryData['delivery_notes'] = deliveryNotes.trim();
      }

      // Add coordinates as numbers (double), not strings
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

      final deliveryResponse = await _client
          .from('deliveries')
          .insert(deliveryData)
          .select('id')
          .single();

      final deliveryId = deliveryResponse['id'] as String;
      debugPrint('✅ Delivery created with ID: $deliveryId');

      // Create delivery items
      final deliveryItems = items.map<Map<String, dynamic>>((item) {
        final priceCents = item['price_cents'] as int;
        final quantity = item['quantity'] as int;
        final subtotal = priceCents * quantity; // Calculate subtotal

        return {
          'delivery_id': deliveryId,
          'product_id': item['menu_item_id'], // menu_item_id maps to merchant_products.id
          'quantity': quantity,
          'subtotal': subtotal / 100.0, // Convert cents to numeric (decimal)
        };
      }).toList();

      await _client.from('delivery_items').insert(deliveryItems);
      debugPrint('✅ Delivery items created: ${deliveryItems.length}');

      debugPrint('=== Delivery Creation Complete ===');
      return deliveryId;
    } catch (e, stackTrace) {
      debugPrint('❌ Error creating delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Find nearby available/active riders
  Future<List<Map<String, dynamic>>> findNearbyRiders({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    try {
      debugPrint('=== Finding Nearby Riders ===');
      debugPrint('Location: $latitude, $longitude');
      debugPrint('Radius: $radiusKm km');

      // Get all available riders with location
      // Note: This fetches all available riders and filters by distance
      // For production, you might want to use PostGIS or a geospatial query
      final riders = await _client
          .from('riders')
          .select('id, latitude, longitude, status, last_active')
          .eq('status', 'available')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);

      debugPrint('Found ${riders.length} available riders');

      // Filter riders within radius and recently active (within last 15 minutes)
      final now = DateTime.now();
      final recentRiders = <Map<String, dynamic>>[];

      for (final rider in riders) {
        final riderLat = rider['latitude'] as double?;
        final riderLng = rider['longitude'] as double?;
        final lastActive = rider['last_active'] as String?;

        if (riderLat == null || riderLng == null) continue;

        // Check if rider was active recently (within last 15 minutes)
        if (lastActive != null) {
          final lastActiveTime = DateTime.parse(lastActive);
          final timeSinceActive = now.difference(lastActiveTime);
          if (timeSinceActive.inMinutes > 15) {
            continue; // Skip inactive riders
          }
        }

        // Calculate distance using haversine formula
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

      // Sort by distance (closest first)
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

  // Calculate distance between two coordinates using haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0; // Earth radius in km
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  // Assign rider to delivery
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
          .update({'rider_id': riderId})
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

  // Get delivery details with rider location
  Future<Map<String, dynamic>?> getDeliveryById(String deliveryId) async {
    try {
      debugPrint('=== Fetching Delivery Details ===');
      debugPrint('Delivery ID: $deliveryId');

      // First get the delivery
      final delivery = await _client
          .from('deliveries')
          .select('*')
          .eq('id', deliveryId)
          .maybeSingle();

      if (delivery == null) {
        debugPrint('⚠️ Delivery not found');
        return null;
      }

      debugPrint('✅ Delivery fetched');
      debugPrint('Status: ${delivery['status']}');
      debugPrint('Rider ID: ${delivery['rider_id']}');

      // If rider is assigned, fetch rider location
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

      // Fetch merchant GCash info for payment
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
            
            // Fallback to phone from users table if gcash_number is not set
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

      return delivery;
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching delivery:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  // Get customer location
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

  // Get customer deliveries with optional status filter
  Future<List<Map<String, dynamic>>> getCustomerDeliveries({
    required String customerId,
    String? status,
  }) async {
    try {
      debugPrint('=== Fetching Customer Deliveries ===');
      debugPrint('Customer ID: $customerId');
      debugPrint('Status filter: ${status ?? 'all'}');

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
              )
            )
          ''')
          .eq('customer_id', customerId);

      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }

      final deliveries = await query.order('created_at', ascending: false);

      debugPrint('✅ Found ${deliveries.length} deliveries');
      return List<Map<String, dynamic>>.from(deliveries);
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching customer deliveries:');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error message: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  // Mark delivery as completed by customer
  Future<void> completeDelivery({
    required String deliveryId,
    required String customerId,
  }) async {
    try {
      debugPrint('=== Completing Delivery ===');
      debugPrint('Delivery ID: $deliveryId');
      debugPrint('Customer ID: $customerId');

      // Verify the delivery belongs to this customer
      final delivery = await _client
          .from('deliveries')
          .select('id, customer_id, status')
          .eq('id', deliveryId)
          .single();

      if (delivery['customer_id'] != customerId) {
        throw Exception('Delivery does not belong to this customer');
      }

      final currentStatus = delivery['status']?.toString().toLowerCase() ?? '';
      
      // Only allow completion if delivery is in 'delivered' status
      // (not if already completed or still in transit)
      if (currentStatus != 'delivered') {
        throw Exception('Delivery must be delivered before it can be marked as completed');
      }

      // Update status to 'completed'
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

  // Submit payment proof for delivery
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

      // Verify the delivery belongs to this customer
      final delivery = await _client
          .from('deliveries')
          .select('id, customer_id, status')
          .eq('id', deliveryId)
          .single();

      if (delivery['customer_id'] != customerId) {
        throw Exception('Delivery does not belong to this customer');
      }

      // Upload payment image to Supabase Storage
      final fileName = 'payment_${deliveryId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageBytes = await paymentImage.readAsBytes();

      await _client.storage
          .from('payment-proofs')
          .uploadBinary(
            fileName,
            imageBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      // Get public URL for the uploaded image
      final imageUrl = _client.storage
          .from('payment-proofs')
          .getPublicUrl(fileName);

      debugPrint('✅ Payment image uploaded: $imageUrl');

      // Store payment information in payments table
      // The payments table now exists, so we'll insert directly
      await _client.from('payments').insert({
        'delivery_id': deliveryId,
        'customer_id': customerId,
        'payment_proof_url': imageUrl,
        'reference_number': referenceNumber,
        'amount': amount,
        'ewallet_name': senderName, // Store sender name in ewallet_name field
        'status': 'pending',
        // created_at has a default value, so we don't need to set it
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
}


