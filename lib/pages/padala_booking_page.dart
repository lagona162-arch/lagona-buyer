import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
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
  final ImagePicker _imagePicker = ImagePicker();
  
  // Parcel photo
  File? _parcelPhoto;
  bool _parcelPhotoUploaded = false;
  String? _parcelPhotoUrl;
  
  // Pickup (Sender) fields
  final TextEditingController _pickupSearchController = TextEditingController();
  final TextEditingController _senderNameController = TextEditingController();
  final TextEditingController _senderPhoneController = TextEditingController();
  final TextEditingController _senderNotesController = TextEditingController();
  LatLng? _pickupLatLng;
  String? _pickupAddress;
  GoogleMapController? _pickupMapController;
  bool _pickupLocationInitialized = false;
  bool _isLoadingPickupLocation = false;
  
  // Dropoff (Recipient) fields
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _recipientPhoneController = TextEditingController();
  final TextEditingController _recipientNotesController = TextEditingController();
  LatLng? _dropoffLatLng;
  String? _dropoffAddress;
  GoogleMapController? _dropoffMapController;
  
  // Package details
  final TextEditingController _packageDescriptionController = TextEditingController();
  
  // UI state
  bool _isLoading = false;
  int _activeStep = 0; // 0: Photo, 1: Pickup, 2: Dropoff, 3: Confirmation
  double? _deliveryFee;
  double? _distance;
  
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
  
  Future<void> _initializePickupLocation() async {
    if (_pickupLocationInitialized) return;
    
    if (mounted) {
      setState(() {
        _isLoadingPickupLocation = true;
      });
    }
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isLoadingPickupLocation = false;
          });
        }
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isLoadingPickupLocation = false;
            });
          }
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoadingPickupLocation = false;
          });
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
        
        if (mounted) {
        setState(() {
            _pickupLatLng = latLng;
            _pickupAddress = address ?? '${latLng.latitude}, ${latLng.longitude}';
            _pickupSearchController.text = _pickupAddress!;
            _pickupLocationInitialized = true;
            _isLoadingPickupLocation = false;
          });
          
          if (_pickupMapController != null) {
            await _pickupMapController!.animateCamera(
              CameraUpdate.newLatLngZoom(latLng, 16),
            );
          }
        }
          } else {
        if (mounted) {
          setState(() {
            _isLoadingPickupLocation = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing pickup location: $e');
      if (mounted) {
        setState(() {
          _isLoadingPickupLocation = false;
        });
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
  
  Future<void> _takeParcelPhoto() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (pickedFile != null && mounted) {
        setState(() {
          _parcelPhoto = File(pickedFile.path);
          _parcelPhotoUploaded = false;
        });
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking photo: $e'),
            backgroundColor: AppColors.error,
          ),
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
    if (mounted) {
    setState(() {
      if (isPickup) {
        _pickupLatLng = latLng;
      } else {
        _dropoffLatLng = latLng;
      }
    });
    }

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
            }
          });

          _calculateDeliveryFee();

          final mapController = isPickup ? _pickupMapController : _dropoffMapController;
          if (mapController != null) {
            await mapController.animateCamera(
              CameraUpdate.newLatLngZoom(latLng, 16),
            );
          } else {
            // If map controller is not ready yet, wait a bit and try again
            await Future.delayed(const Duration(milliseconds: 300));
            final retryController = isPickup ? _pickupMapController : _dropoffMapController;
            if (retryController != null) {
              await retryController.animateCamera(
              CameraUpdate.newLatLngZoom(latLng, 16),
            );
            }
          }
          
          // Update map preview to show the new location
          if (mounted && !isPickup) {
            // For dropoff, ensure the preview map updates
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _dropoffMapController != null && _dropoffLatLng != null) {
                _dropoffMapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(_dropoffLatLng!, 16),
                );
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      if (mounted) {
        final coords = '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
        setState(() {
          if (isPickup) {
            _pickupAddress = coords;
            _pickupSearchController.text = coords;
          } else {
            _dropoffAddress = coords;
          }
        });
        _calculateDeliveryFee();
      }
    }
  }
  
  void _calculateDeliveryFee() {
    if (_pickupLatLng == null || _dropoffLatLng == null) {
      setState(() {
        _deliveryFee = null;
        _distance = null;
      });
      return;
    }

    final distance = haversineKm(
      _pickupLatLng!.latitude,
      _pickupLatLng!.longitude,
      _dropoffLatLng!.latitude,
      _dropoffLatLng!.longitude,
    );

    debugPrint('📍 Padala delivery distance calculated: ${distance.toStringAsFixed(2)} km');

    double fee = 55.0; 
    if (distance > 1.0) {
      final additionalKm = distance - 1.0; // Use actual decimal distance, not rounded up
      fee += additionalKm * 10.0;
      debugPrint('💰 Additional km: ${additionalKm.toStringAsFixed(2)}, Fee: ₱${(additionalKm * 10.0).toStringAsFixed(2)}');
    }

    debugPrint('💰 Total Padala delivery fee: ₱${fee.toStringAsFixed(2)}');

    setState(() {
      _distance = distance;
      _deliveryFee = fee;
    });
  }
  
  Future<void> _uploadParcelPhoto() async {
    if (_parcelPhoto == null || _parcelPhotoUploaded) return;
    
    try {
      setState(() => _isLoading = true);
      
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');
      
      final fileBytes = await _parcelPhoto!.readAsBytes();
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = fileName;
      
      debugPrint('📤 Uploading parcel photo to parcel-photos bucket...');
      debugPrint('   File: $fileName');
      debugPrint('   Size: ${fileBytes.length} bytes');
      
      await Supabase.instance.client.storage
          .from('parcel-photos')
          .uploadBinary(
            filePath,
            fileBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      
      final imageUrl = Supabase.instance.client.storage
          .from('parcel-photos')
          .getPublicUrl(filePath);
      
      debugPrint('✅ Parcel photo uploaded successfully');
      debugPrint('✅ Photo URL: $imageUrl');
      
      if (mounted) {
        setState(() {
          _parcelPhotoUrl = imageUrl;
          _parcelPhotoUploaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error uploading parcel photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photo: $e'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
        // Allow booking to proceed even if photo upload fails
        // The photo can be uploaded later or the rider will take photos
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _bookPadala() async {
    // Validate form if it's available (only for pickup and dropoff steps)
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }
    
    if (_parcelPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take a photo of the parcel')),
      );
      return;
    }
    
    if (_pickupLatLng == null || _pickupAddress == null || _pickupAddress!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a pickup location')),
      );
      return;
    }
    
    // Validate dropoff address is required
    if (_dropoffLatLng == null || _dropoffAddress == null || _dropoffAddress!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dropoff address is required. Please select a dropoff location on the map.'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ),
      );
      // Go back to dropoff step
      setState(() => _activeStep = 2);
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Upload parcel photo if not already uploaded
      // If upload fails, proceed anyway (rider will take photos)
      if (!_parcelPhotoUploaded && _parcelPhoto != null) {
        try {
          await _uploadParcelPhoto();
        } catch (e) {
          debugPrint('⚠️ Photo upload failed, but proceeding with booking: $e');
          // Continue with booking even if photo upload fails
          // The rider will take photos during pickup
        }
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
        parcelPhotoUrl: _parcelPhotoUrl,
      );
      
      if (!mounted) return;
      
        // Navigate to finding rider page
        final result = await Navigator.of(context).pushReplacementNamed(
          FindingRiderPage.routeName,
          arguments: padalaId,
        );
      
        if (result == true && mounted) {
          Navigator.of(context).pop(true);
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
  
  Widget _buildPhotoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Take Photo of Parcel',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please take a clear photo of the parcel you want to deliver',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          
          GestureDetector(
            onTap: _takeParcelPhoto,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: _parcelPhoto != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _parcelPhoto!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tap to take photo',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          
          if (_parcelPhoto != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _takeParcelPhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Retake Photo'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildPickupStep() {
    // Initialize pickup location when step is shown
    if (!_pickupLocationInitialized && _activeStep == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializePickupLocation();
      });
    }
    
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
            const SizedBox(height: 8),
            Text(
              'Your current location is automatically detected, but you can change it',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            
            // Address display
            TextFormField(
              controller: _pickupSearchController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Pickup Address',
                prefixIcon: _isLoadingPickupLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.location_on),
                suffixIcon: _isLoadingPickupLocation
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.edit_location),
                        onPressed: () => _openMapModal(true),
                        tooltip: 'Change location',
                ),
                hintText: _isLoadingPickupLocation
                    ? 'Fetching your location...'
                    : null,
              ),
              validator: (value) {
                if (_pickupAddress == null) {
                  return 'Please select a pickup address';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Map Preview
            GestureDetector(
              onTap: () => _openMapModal(true),
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
                      if (_isLoadingPickupLocation)
                        Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'Loading your location...',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
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
                            if (_pickupLatLng != null) {
                              controller.animateCamera(
                                CameraUpdate.newLatLngZoom(_pickupLatLng!, 16),
                              );
                            }
                        },
                      ),
                      // Zoom controls - positioned at bottom right to avoid overlap
                      if (!_isLoadingPickupLocation && _pickupMapController != null)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                                elevation: 4,
                                shadowColor: Colors.black26,
                                child: InkWell(
                                  onTap: () {
                                    _pickupMapController!.animateCamera(
                                      CameraUpdate.zoomIn(),
                                    );
                                  },
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    topRight: Radius.circular(8),
                                  ),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(8),
                                      ),
                                      border: Border.all(color: Colors.grey[300]!, width: 1),
                                    ),
                                    child: const Icon(Icons.add, size: 22, color: Colors.black87),
                                  ),
                                ),
                              ),
                              Container(
                                width: 44,
                                height: 1,
                                color: Colors.grey[300],
                              ),
                              Material(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                                elevation: 4,
                                shadowColor: Colors.black26,
                                child: InkWell(
                                  onTap: () {
                                    _pickupMapController!.animateCamera(
                                      CameraUpdate.zoomOut(),
                                    );
                                  },
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(8),
                                        bottomRight: Radius.circular(8),
                                      ),
                                      border: Border.all(color: Colors.grey[300]!, width: 1),
                                    ),
                                    child: const Icon(Icons.remove, size: 22, color: Colors.black87),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Tap to change overlay
                      if (!_isLoadingPickupLocation)
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
      child: Form(
        key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
        children: [
          const Text(
            'Dropoff Location (Recipient)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '*',
                  style: TextStyle(
                    fontSize: 20,
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select the dropoff location on the map (Required)',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            if (_dropoffLatLng == null || _dropoffAddress == null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dropoff location is required to proceed',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
            ),
          ),
          const SizedBox(height: 16),
          
            // Address display
          TextFormField(
              readOnly: true,
              controller: TextEditingController(text: _dropoffAddress ?? ''),
            decoration: InputDecoration(
                labelText: 'Dropoff Address *',
                prefixIcon: const Icon(Icons.flag),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.map),
                  onPressed: () => _openMapModal(false),
                  tooltip: 'Select on map',
              ),
            ),
            validator: (value) {
                if (_dropoffLatLng == null || _dropoffAddress == null || _dropoffAddress!.isEmpty) {
                  return 'Please select a dropoff location on the map';
              }
              return null;
            },
          ),
          
            const SizedBox(height: 16),
            
            // Map for selection
          GestureDetector(
            onTap: () => _openMapModal(false),
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    GoogleMap(
                      key: ValueKey(_dropoffLatLng?.toString() ?? 'dropoff_map'),
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
                        if (_dropoffLatLng != null) {
                          controller.animateCamera(
                            CameraUpdate.newLatLngZoom(_dropoffLatLng!, 16),
                          );
                        }
                      },
                    ),
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
      ),
    );
  }
  
  Widget _buildConfirmationStep() {
    // Calculate fee if not already calculated
    if (_deliveryFee == null && _pickupLatLng != null && _dropoffLatLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateDeliveryFee();
      });
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Confirm Delivery Details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Parcel Photo
          if (_parcelPhoto != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
          const Text(
                      'Parcel Photo',
            style: TextStyle(
              fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _parcelPhoto!,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Pickup Details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                  const Text(
                    'Pickup',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                          fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_pickupAddress ?? 'Not set'),
                  const SizedBox(height: 8),
                  Text('Sender: ${_senderNameController.text}'),
                  Text('Phone: ${_senderPhoneController.text}'),
                  if (_senderNotesController.text.trim().isNotEmpty)
                    Text('Notes: ${_senderNotesController.text.trim()}'),
                ],
              ),
            ),
          ),
          
                  const SizedBox(height: 16),
          
          // Dropoff Details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                  const Text(
                    'Dropoff',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                          fontSize: 16,
                      color: AppColors.error,
                    ),
                  ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_dropoffAddress ?? 'Not set'),
                  const SizedBox(height: 8),
                  Text('Recipient: ${_recipientNameController.text}'),
                  Text('Phone: ${_recipientPhoneController.text}'),
                  if (_recipientNotesController.text.trim().isNotEmpty)
                    Text('Notes: ${_recipientNotesController.text.trim()}'),
                ],
              ),
            ),
          ),
          
          if (_packageDescriptionController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Package Description',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_packageDescriptionController.text.trim()),
                  ],
                ),
              ),
            ),
          ],
          
                  const SizedBox(height: 16),
          
          // Delivery Fee Breakdown
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivery Fee Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_distance != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                        Text(
                          'Distance',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        Text(
                          '${_distance!.toStringAsFixed(2)} km',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Base Fee (First km)',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const Text(
                        '₱55.00',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  
                  if (_distance != null && _distance! > 1.0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Additional Fee (${(_distance! - 1.0).toStringAsFixed(2)} km × ₱10.00)',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        Text(
                          '₱${((_distance! - 1.0) * 10.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                  
                  const Divider(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Delivery Fee',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        _deliveryFee != null
                            ? '₱${_deliveryFee!.toStringAsFixed(2)}'
                            : 'Calculating...',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                _buildStepIndicator(0, 'Photo'),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _activeStep > 0 ? AppColors.primary : AppColors.border,
                  ),
                ),
                _buildStepIndicator(1, 'Pickup'),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _activeStep > 1 ? AppColors.primary : AppColors.border,
                  ),
                ),
                _buildStepIndicator(2, 'Dropoff'),
                Expanded(
                  child: Container(
                    height: 2,
                    color: _activeStep > 2 ? AppColors.primary : AppColors.border,
                  ),
                ),
                _buildStepIndicator(3, 'Confirm'),
              ],
            ),
          ),
          
          // Form content
          Expanded(
            child: _activeStep == 0
                ? _buildPhotoStep()
                : _activeStep == 1
                    ? _buildPickupStep()
                    : _activeStep == 2
                        ? _buildDropoffStep()
                        : _buildConfirmationStep(),
          ),
          
          // Navigation buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_activeStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () {
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
                            if (_activeStep < 3) {
                              if (_activeStep == 0) {
                                // Photo step - just need photo
                                if (_parcelPhoto == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please take a photo of the parcel')),
                                  );
                                  return;
                                }
                                setState(() => _activeStep++);
                              } else if (_activeStep == 1 || _activeStep == 2) {
                                // Pickup/Dropoff steps - validate form
                              if (_formKey.currentState?.validate() ?? false) {
                                  // Additional validation for dropoff step
                                  if (_activeStep == 2) {
                                    if (_dropoffLatLng == null || _dropoffAddress == null || _dropoffAddress!.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please select a dropoff location on the map'),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                      return;
                                    }
                                    if (_pickupLatLng != null && _dropoffLatLng != null) {
                                  _calculateDeliveryFee();
                                    }
                                }
                                setState(() => _activeStep++);
                                }
                              }
                            } else {
                              // Confirmation step - book delivery
                              _bookPadala();
                            }
                          },
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_activeStep < 3 ? 'Next' : 'Confirm & Book'),
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
          zoomControlsEnabled: false, // Disable default controls, use custom ones
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
        // Custom zoom controls - positioned on LEFT side, always visible
        Positioned(
          top: 100, // Position below AppBar (AppBar ~56px + padding)
          left: 16, // Left side to avoid my location button on right
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

