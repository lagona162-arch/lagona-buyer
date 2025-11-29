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
      
      
      if (lat != null && lng != null) {
        
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
        
        
        if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
          
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
      
      
      if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
        if (lat != null && lng != null) {
          address = 'Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
        } else {
          address = 'Address not available';
        }
      }
      
      
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
      
      
      var address = row['address'] as String?;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      
      
      
      if (lat != null && lng != null) {
        
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
        
        
        if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
          
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
      
      
      if (address == null || address.isEmpty || _looksLikeCoordinates(address)) {
        if (lat != null && lng != null) {
          
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

  
  Future<List<MenuItem>> getMerchantProducts(String merchantId) async {
    final rows = await _client
        .from('merchant_products')
        .select('id,merchant_id,name,category,price,stock')
        .eq('merchant_id', merchantId);
    return (rows as List).map((e) => MenuItem.fromMap(Map<String, dynamic>.from(e))).toList();
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
          
          
          final formattedAddress = results.first['formatted_address'] as String?;
          
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            
            String address = formattedAddress;
            
            
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

  
  bool _looksLikeCoordinates(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final trimmed = value.trim();
    
    
    final coordPattern = RegExp(r'^-?\d+\.?\d*\s*,\s*-?\d+\.?\d*$');
    final locationAtPattern = RegExp(r'^Location at \d+\.?\d*,\s*\d+\.?\d*$', caseSensitive: false);
    return coordPattern.hasMatch(trimmed) || locationAtPattern.hasMatch(trimmed);
  }
  
  
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
          
          final formattedAddress = results.first['formatted_address'] as String?;
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            
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
      debugPrint('Items: ${items.length}');

      
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

      
      if ((pickupAddress == null || pickupAddress.isEmpty || pickupAddress.length < 10) &&
          merchantLat != null && merchantLng != null) {
        debugPrint('Merchant address is missing or vague, using reverse geocoding...');
        pickupAddress = await _reverseGeocode(
          merchantLat.toDouble(),
          merchantLng.toDouble(),
        );
        
        pickupAddress ??= merchantAddress ?? 'Unknown location';
      }

      
      if (_looksLikeCoordinates(dropoffAddress) && customerLat != null && customerLng != null) {
        debugPrint('Customer address appears to be coordinates, using reverse geocoding...');
        dropoffAddress = await _reverseGeocode(
          customerLat.toDouble(),
          customerLng.toDouble(),
        );
        
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
        
        dropoffAddress ??= 'Location at ${customerLat.toStringAsFixed(6)}, ${customerLng.toStringAsFixed(6)}';
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

      final deliveryResponse = await _client
          .from('deliveries')
          .insert(deliveryData)
          .select('id')
          .single();

      final deliveryId = deliveryResponse['id'] as String;
      debugPrint('✅ Delivery created with ID: $deliveryId');

      
      final deliveryItems = items.map<Map<String, dynamic>>((item) {
        final priceCents = item['price_cents'] as int;
        final quantity = item['quantity'] as int;
        final subtotal = priceCents * quantity; 

        return {
          'delivery_id': deliveryId,
          'product_id': item['menu_item_id'], 
          'quantity': quantity,
          'subtotal': subtotal / 100.0, 
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
}


