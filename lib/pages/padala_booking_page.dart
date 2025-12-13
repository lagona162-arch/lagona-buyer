import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/maps_config.dart';
import '../services/supabase_service.dart';
import '../services/rider_search_service.dart';
import '../theme/app_colors.dart';
import '../utils/geo.dart';
import 'finding_rider_page.dart';
import 'padala_tracking_page.dart';
import 'service_selection_page.dart';

class PadalaBookingPage extends StatefulWidget {
  static const String routeName = '/padala';
  const PadalaBookingPage({super.key});

  @override
  State<PadalaBookingPage> createState() => _PadalaBookingPageState();
}

class _PadalaBookingPageState extends State<PadalaBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseService _supabaseService = SupabaseService();
  final RiderSearchService _riderSearchService = RiderSearchService();
  
  // Pickup (Sender) fields
  final TextEditingController _pickupSearchController = TextEditingController();
  final TextEditingController _senderNameController = TextEditingController();
  final TextEditingController _senderPhoneController = TextEditingController();
  final TextEditingController _senderNotesController = TextEditingController();
  LatLng? _pickupLatLng;
  String? _pickupAddress;
  List<Map<String, String>> _pickupPredictions = [];
  GoogleMapController? _pickupMapController;
  
  // Dropoff (Recipient) fields
  final TextEditingController _dropoffSearchController = TextEditingController();
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _recipientPhoneController = TextEditingController();
  final TextEditingController _recipientNotesController = TextEditingController();
  LatLng? _dropoffLatLng;
  String? _dropoffAddress;
  List<Map<String, String>> _dropoffPredictions = [];
  GoogleMapController? _dropoffMapController;
  
  // Package details
  final TextEditingController _packageDescriptionController = TextEditingController();
  
  // UI state
  bool _isLoading = false;
  int _activeStep = 0; // 0: Pickup, 1: Dropoff, 2: Details, 3: Review
  double? _deliveryFee;
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkExistingPadala();
  }

  Future<void> _checkExistingPadala() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final existingPadala = await _supabaseService.getCustomerPadalaDeliveries(
        customerId: user.id,
      );
      
      final hasActivePadala = existingPadala.any((d) {
        final status = (d['status']?.toString().toLowerCase() ?? '').trim();
        return status != 'delivered' && 
               status != 'completed' && 
               status != 'cancelled';
      });
      
      if (hasActivePadala && mounted) {
        // Show warning banner
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '⚠️ You already have an active Padala delivery. Please complete or cancel it first.',
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
      debugPrint('Error checking existing Padala: $e');
    }
  }
  
  @override
  void dispose() {
    _pickupSearchController.dispose();
    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _senderNotesController.dispose();
    _dropoffSearchController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _recipientNotesController.dispose();
    _packageDescriptionController.dispose();
    _pickupMapController?.dispose();
    _dropoffMapController?.dispose();
    super.dispose();
  }
  
  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final response = await Supabase.instance.client
            .from('users')
            .select('firstname, lastname, phone')
            .eq('id', user.id)
            .single();
        
        if (mounted) {
          final firstName = response['firstname'] ?? '';
          final lastName = response['lastname'] ?? '';
          _senderNameController.text = '$firstName $lastName'.trim();
          _senderPhoneController.text = response['phone'] ?? '';
        }
      } catch (e) {
        debugPrint('Error loading user data: $e');
      }
    }
  }
  
  String? _validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.trim().replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    final phPattern = RegExp(r'^09\d{9}$');
    if (phPattern.hasMatch(cleaned)) {
      return null;
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      final converted = '0${cleaned.substring(2)}';
      if (phPattern.hasMatch(converted)) {
        return null;
      }
    }
    return 'Invalid phone number. Must be 11 digits starting with 09';
  }
  
  Future<void> _fetchAutocomplete(String input, bool isPickup) async {
    if (input.trim().isEmpty) {
      setState(() {
        if (isPickup) {
          _pickupPredictions = [];
        } else {
          _dropoffPredictions = [];
        }
      });
      return;
    }
    
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': input,
        'key': MapsConfig.apiKey,
        'components': 'country:ph',
      },
    );
    
    try {
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final preds = (data['predictions'] as List?)
            ?.map((p) => {
                  'description': p['description'] as String,
                  'place_id': p['place_id'] as String,
                })
            .toList() ?? [];
        
        setState(() {
          if (isPickup) {
            _pickupPredictions = preds;
          } else {
            _dropoffPredictions = preds;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching autocomplete: $e');
    }
  }
  
  Future<void> _selectPlace(String placeId, String description, bool isPickup) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'key': MapsConfig.apiKey,
        'fields': 'geometry/location,formatted_address',
      },
    );
    
    try {
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final loc = data['result']['geometry']['location'] as Map<String, dynamic>;
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final address = data['result']['formatted_address'] as String? ?? description;
        
        setState(() {
          if (isPickup) {
            _pickupLatLng = LatLng(lat, lng);
            _pickupAddress = address;
            _pickupSearchController.text = address;
            _pickupPredictions = [];
          } else {
            _dropoffLatLng = LatLng(lat, lng);
            _dropoffAddress = address;
            _dropoffSearchController.text = address;
            _dropoffPredictions = [];
          }
        });
        
        // Calculate delivery fee when both locations are set
        _calculateDeliveryFee();
        
        final mapController = isPickup ? _pickupMapController : _dropoffMapController;
        if (mapController != null) {
          await mapController.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
          );
        }
      }
    } catch (e) {
      debugPrint('Error selecting place: $e');
    }
  }
  
  Future<void> _getCurrentLocation(bool isPickup) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled')),
          );
        }
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required')),
            );
          }
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission was permanently denied')),
          );
        }
        return;
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final latLng = LatLng(position.latitude, position.longitude);
      
      // Reverse geocode to get address
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '${latLng.latitude},${latLng.longitude}',
          'key': MapsConfig.apiKey,
        },
      );
      
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        final address = results.isNotEmpty
            ? results.first['formatted_address'] as String?
            : '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
        
        setState(() {
          if (isPickup) {
            _pickupLatLng = latLng;
            _pickupAddress = address ?? '${latLng.latitude}, ${latLng.longitude}';
            _pickupSearchController.text = _pickupAddress!;
          } else {
            _dropoffLatLng = latLng;
            _dropoffAddress = address ?? '${latLng.latitude}, ${latLng.longitude}';
            _dropoffSearchController.text = _dropoffAddress!;
          }
        });
        
        // Calculate delivery fee when both locations are set
        _calculateDeliveryFee();
        
        final mapController = isPickup ? _pickupMapController : _dropoffMapController;
        if (mapController != null) {
          await mapController.animateCamera(
            CameraUpdate.newLatLngZoom(latLng, 16),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }
  
  Future<void> _openMapModal(bool isPickup) async {
    final initialPosition = isPickup ? _pickupLatLng : _dropoffLatLng;
    
    final result = await showDialog<LatLng>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              // Header
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
                    Icon(
                      isPickup ? Icons.location_on : Icons.flag,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPickup ? 'Select Pickup Location' : 'Select Dropoff Location',
                        style: const TextStyle(
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
              // Map
              Expanded(
                child: _MapSelector(
                  initialPosition: initialPosition ?? const LatLng(14.5995, 120.9842),
                  isPickup: isPickup,
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
      await _updateLocationFromMap(result, isPickup);
    }
  }

  Future<void> _updateLocationFromMap(LatLng latLng, bool isPickup) async {
    // Update the location immediately for visual feedback
    setState(() {
      if (isPickup) {
        _pickupLatLng = latLng;
      } else {
        _dropoffLatLng = latLng;
      }
    });

    // Reverse geocode to get address
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '${latLng.latitude},${latLng.longitude}',
          'key': MapsConfig.apiKey,
        },
      );

      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        final address = results.isNotEmpty
            ? results.first['formatted_address'] as String?
            : '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';

        if (mounted) {
          setState(() {
            if (isPickup) {
              _pickupAddress = address ?? '${latLng.latitude}, ${latLng.longitude}';
              _pickupSearchController.text = _pickupAddress!;
            } else {
              _dropoffAddress = address ?? '${latLng.latitude}, ${latLng.longitude}';
              _dropoffSearchController.text = _dropoffAddress!;
            }
          });

          // Calculate delivery fee
          _calculateDeliveryFee();

          // Animate camera to center on the new location
          final mapController = isPickup ? _pickupMapController : _dropoffMapController;
          if (mapController != null) {
            await mapController.animateCamera(
              CameraUpdate.newLatLngZoom(latLng, 16),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      // Even if reverse geocoding fails, update with coordinates
      if (mounted) {
        final coords = '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
        setState(() {
          if (isPickup) {
            _pickupAddress = coords;
            _pickupSearchController.text = coords;
          } else {
            _dropoffAddress = coords;
            _dropoffSearchController.text = coords;
          }
        });
        _calculateDeliveryFee();
      }
    }
  }
  
  void _calculateDeliveryFee() {
    if (_pickupLatLng == null || _dropoffLatLng == null) {
      setState(() => _deliveryFee = null);
      return;
    }

    // Calculate distance between pickup and dropoff locations
    final distance = haversineKm(
      _pickupLatLng!.latitude,
      _pickupLatLng!.longitude,
      _dropoffLatLng!.latitude,
      _dropoffLatLng!.longitude,
    );

    debugPrint('📍 Padala delivery distance calculated: ${distance.toStringAsFixed(2)} km');

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

    debugPrint('💰 Total Padala delivery fee: ₱${fee.toStringAsFixed(2)}');

    setState(() {
      _deliveryFee = fee;
    });
  }
  
  Future<void> _bookPadala() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_pickupLatLng == null || _pickupAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a pickup location')),
      );
      return;
    }
    
    if (_dropoffLatLng == null || _dropoffAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a dropoff location')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Check for existing active Padala deliveries
      final existingPadala = await _supabaseService.getCustomerPadalaDeliveries(
        customerId: user.id,
      );
      
      final hasActivePadala = existingPadala.any((d) {
        final status = (d['status']?.toString().toLowerCase() ?? '').trim();
        return status != 'delivered' && 
               status != 'completed' && 
               status != 'cancelled';
      });
      
      if (hasActivePadala) {
        if (mounted) {
          setState(() => _isLoading = false);
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Active Padala Delivery'),
              content: const Text(
                'You already have an active Padala delivery in progress.\n\n'
                'Please wait for it to complete or cancel it before booking another Padala delivery.',
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
      
      // Create Padala booking
      final padalaId = await _supabaseService.createPadalaBooking(
        customerId: user.id,
        pickupAddress: _pickupAddress!,
        pickupLatitude: _pickupLatLng!.latitude,
        pickupLongitude: _pickupLatLng!.longitude,
        senderName: _senderNameController.text.trim(),
        senderPhone: _senderPhoneController.text.trim(),
        senderNotes: _senderNotesController.text.trim().isEmpty 
            ? null 
            : _senderNotesController.text.trim(),
        dropoffAddress: _dropoffAddress!,
        dropoffLatitude: _dropoffLatLng!.latitude,
        dropoffLongitude: _dropoffLatLng!.longitude,
        recipientName: _recipientNameController.text.trim(),
        recipientPhone: _recipientPhoneController.text.trim(),
        recipientNotes: _recipientNotesController.text.trim().isEmpty 
            ? null 
            : _recipientNotesController.text.trim(),
        packageDescription: _packageDescriptionController.text.trim().isEmpty 
            ? null 
            : _packageDescriptionController.text.trim(),
        deliveryFee: _deliveryFee,
      );
      
      if (!mounted) return;
      
      // Find and assign rider
      final riderMatch = await _riderSearchService.findNearbyRider(
        _pickupLatLng!,
        radiusKm: 5.0,
      );
      
      if (riderMatch != null) {
        await _supabaseService.assignRiderToPadala(
          padalaId: padalaId,
          riderId: riderMatch.riderId,
        );
        
        if (!mounted) return;
        
        // Navigate to tracking page
        Navigator.of(context).pushReplacementNamed(
          PadalaTrackingPage.routeName,
          arguments: padalaId,
        );
      } else {
        // Navigate to finding rider page
        final result = await Navigator.of(context).pushReplacementNamed(
          FindingRiderPage.routeName,
          arguments: padalaId,
        );
        // If cancelled, pop back to service selection with result
        if (result == true && mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error booking Padala: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
  
  Widget _buildPickupStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pickup Location (Sender)',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Address search
            TextFormField(
              controller: _pickupSearchController,
              decoration: InputDecoration(
                labelText: 'Pickup Address',
                hintText: 'Search for address',
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _getCurrentLocation(true),
                ),
              ),
              onChanged: (value) => _fetchAutocomplete(value, true),
              validator: (value) {
                if (_pickupAddress == null && (value == null || value.isEmpty)) {
                  return 'Please select a pickup address';
                }
                return null;
              },
            ),
            
            // Autocomplete suggestions
            if (_pickupPredictions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _pickupPredictions.length,
                  itemBuilder: (context, index) {
                    final pred = _pickupPredictions[index];
                    return ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(pred['description']!),
                      onTap: () => _selectPlace(
                        pred['place_id']!,
                        pred['description']!,
                        true,
                      ),
                    );
                  },
                ),
              ),
            
            // Map Preview
            GestureDetector(
              onTap: () => _openMapModal(true),
              child: Container(
                height: 200,
                margin: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _pickupLatLng ?? const LatLng(14.5995, 120.9842),
                          zoom: _pickupLatLng != null ? 15 : 12,
                        ),
                        markers: _pickupLatLng != null
                            ? {
                                Marker(
                                  markerId: const MarkerId('pickup'),
                                  position: _pickupLatLng!,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueGreen,
                                  ),
                                ),
                              }
                            : {},
                        zoomGesturesEnabled: false,
                        scrollGesturesEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        onMapCreated: (controller) {
                          _pickupMapController = controller;
                        },
                      ),
                      // Overlay to indicate it's tappable
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
                                  'Tap to select location',
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
            
            // Sender details
            TextFormField(
              controller: _senderNameController,
              decoration: const InputDecoration(
                labelText: 'Sender Name',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Sender name is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _senderPhoneController,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              decoration: const InputDecoration(
                labelText: 'Sender Phone',
                hintText: '09XXXXXXXXX',
                prefixIcon: Icon(Icons.phone),
                counterText: '',
              ),
              validator: _validatePhoneNumber,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _senderNotesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDropoffStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Dropoff Location (Recipient)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Address search
          TextFormField(
            controller: _dropoffSearchController,
            decoration: InputDecoration(
              labelText: 'Dropoff Address',
              hintText: 'Search for address',
              prefixIcon: const Icon(Icons.location_on),
              suffixIcon: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: () => _getCurrentLocation(false),
              ),
            ),
            onChanged: (value) => _fetchAutocomplete(value, false),
            validator: (value) {
              if (_dropoffAddress == null && (value == null || value.isEmpty)) {
                return 'Please select a dropoff address';
              }
              return null;
            },
          ),
          
          // Autocomplete suggestions
          if (_dropoffPredictions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _dropoffPredictions.length,
                itemBuilder: (context, index) {
                  final pred = _dropoffPredictions[index];
                  return ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(pred['description']!),
                    onTap: () => _selectPlace(
                      pred['place_id']!,
                      pred['description']!,
                      false,
                    ),
                  );
                },
              ),
            ),
          
          // Map Preview
          GestureDetector(
            onTap: () => _openMapModal(false),
            child: Container(
              height: 200,
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _dropoffLatLng ?? const LatLng(14.5995, 120.9842),
                        zoom: _dropoffLatLng != null ? 15 : 12,
                      ),
                      markers: _dropoffLatLng != null
                          ? {
                              Marker(
                                markerId: const MarkerId('dropoff'),
                                position: _dropoffLatLng!,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueRed,
                                ),
                              ),
                            }
                          : {},
                      zoomGesturesEnabled: false,
                      scrollGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      onMapCreated: (controller) {
                        _dropoffMapController = controller;
                      },
                    ),
                    // Overlay to indicate it's tappable
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
                                'Tap to select location',
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
          
          // Recipient details
          TextFormField(
            controller: _recipientNameController,
            decoration: const InputDecoration(
              labelText: 'Recipient Name',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) =>
                value?.trim().isEmpty ?? true ? 'Recipient name is required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _recipientPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: const InputDecoration(
              labelText: 'Recipient Phone',
              hintText: '09XXXXXXXXX',
              prefixIcon: Icon(Icons.phone),
              counterText: '',
            ),
            validator: _validatePhoneNumber,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _recipientNotesController,
            decoration: const InputDecoration(
              labelText: 'Notes (Optional)',
              prefixIcon: Icon(Icons.note),
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Package Details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _packageDescriptionController,
            decoration: const InputDecoration(
              labelText: 'Package Description (Optional)',
              hintText: 'e.g., Documents, Small package, etc.',
              prefixIcon: Icon(Icons.inventory_2),
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 24),
          const Text(
            'Review',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pickup',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_pickupAddress ?? 'Not set'),
                  Text(_senderNameController.text),
                  Text(_senderPhoneController.text),
                  const SizedBox(height: 16),
                  const Text(
                    'Dropoff',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_dropoffAddress ?? 'Not set'),
                  Text(_recipientNameController.text),
                  Text(_recipientPhoneController.text),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Delivery Fee',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _deliveryFee != null
                            ? '₱${_deliveryFee!.toStringAsFixed(2)}'
                            : 'Calculating...',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  if (_deliveryFee == null && _pickupLatLng != null && _dropoffLatLng != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Please wait while we calculate the fee...',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Padala Delivery'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_activeStep > 0) {
              setState(() => _activeStep--);
            } else {
              Navigator.of(context).pushReplacementNamed(ServiceSelectionPage.routeName);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Pickup'),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _activeStep > 0 ? AppColors.primary : AppColors.border,
                  ),
                ),
                _buildStepIndicator(1, 'Dropoff'),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _activeStep > 1 ? AppColors.primary : AppColors.border,
                  ),
                ),
                _buildStepIndicator(2, 'Details'),
              ],
            ),
          ),
          
          // Form content
          Expanded(
            child: IndexedStack(
              index: _activeStep,
              children: [
                _buildPickupStep(),
                _buildDropoffStep(),
                _buildDetailsStep(),
              ],
            ),
          ),
          
          // Navigation buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_activeStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _activeStep--);
                      },
                      child: const Text('Back'),
                    ),
                  ),
                if (_activeStep > 0) const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            if (_activeStep < 2) {
                              if (_formKey.currentState?.validate() ?? false) {
                                // Calculate delivery fee before moving to details step
                                if (_activeStep == 1 && _pickupLatLng != null && _dropoffLatLng != null) {
                                  _calculateDeliveryFee();
                                }
                                setState(() => _activeStep++);
                              }
                            } else {
                              _bookPadala();
                            }
                          },
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_activeStep < 2 ? 'Next' : 'Book Delivery'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStepIndicator(int step, String label) {
    final isActive = _activeStep == step;
    final isCompleted = _activeStep > step;
    
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive || isCompleted
                ? AppColors.primary
                : AppColors.border,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive || isCompleted
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive || isCompleted
                ? AppColors.primary
                : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// Map Selector Widget for Modal
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
          zoomControlsEnabled: true,
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
        // Confirm button
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
