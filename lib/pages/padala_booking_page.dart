import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _itemDetailsController = TextEditingController();
  final TextEditingController _itemWeightController = TextEditingController();
  final TextEditingController _itemQuantityController = TextEditingController();
  bool _needsThermalBag = false;
  bool _needsAbono = false;
  
  // UI state
  bool _isLoading = false;
  int _activeStep = 0; // 0: Photo & Details, 1: Pickup Location, 2: Dropoff Location, 3: Confirmation
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
                    Navigator.of(context).pushReplacementNamed('/service-selection');
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
    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _senderNotesController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _recipientNotesController.dispose();
    _itemDetailsController.dispose();
    _itemWeightController.dispose();
    _itemQuantityController.dispose();
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
    
    setState(() => _isLoadingPickupLocation = true);
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingPickupLocation = false);
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingPickupLocation = false);
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingPickupLocation = false);
        return;
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final latLng = LatLng(position.latitude, position.longitude);
      final address = await _reverseGeocode(latLng);
      
      if (mounted) {
        setState(() {
          _pickupLatLng = latLng;
          _pickupAddress = address;
          _pickupLocationInitialized = true;
          _isLoadingPickupLocation = false;
        });
        
        _pickupMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(latLng, 16),
        );
      }
    } catch (e) {
      debugPrint('Error initializing pickup location: $e');
      if (mounted) setState(() => _isLoadingPickupLocation = false);
    }
  }
  
  Future<String> _reverseGeocode(LatLng latLng) async {
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
        return results.isNotEmpty
            ? results.first['formatted_address'] as String
            : '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
    }
    return '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
  }
  
  String? _validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.trim().replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    final phPattern = RegExp(r'^09\d{9}$');
    if (phPattern.hasMatch(cleaned)) return null;
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      final converted = '0${cleaned.substring(2)}';
      if (phPattern.hasMatch(converted)) return null;
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
                  onLocationSelected: (latLng) => Navigator.of(context).pop(latLng),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    
    if (result != null) await _updateLocationFromMap(result, isPickup);
  }

  Future<void> _updateLocationFromMap(LatLng latLng, bool isPickup) async {
    setState(() {
      if (isPickup) {
        _pickupLatLng = latLng;
      } else {
        _dropoffLatLng = latLng;
      }
    });

    final address = await _reverseGeocode(latLng);
    
    if (mounted) {
      setState(() {
        if (isPickup) {
          _pickupAddress = address;
        } else {
          _dropoffAddress = address;
        }
      });

      _calculateDeliveryFee();

      final mapController = isPickup ? _pickupMapController : _dropoffMapController;
      await Future.delayed(const Duration(milliseconds: 100));
      mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
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

    double fee = 55.0; 
    if (distance > 1.0) {
      fee += (distance - 1.0) * 10.0;
    }
    
    if (_needsAbono) fee += 55.0;

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
      
      await Supabase.instance.client.storage
          .from('parcel-photos')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      
      final imageUrl = Supabase.instance.client.storage
          .from('parcel-photos')
          .getPublicUrl(fileName);
      
      if (mounted) {
        setState(() {
          _parcelPhotoUrl = imageUrl;
          _parcelPhotoUploaded = true;
        });
      }
    } catch (e) {
      debugPrint('Error uploading parcel photo: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _bookPadala() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) return;
    
    if (_parcelPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take a photo of the parcel')),
      );
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
        const SnackBar(
          content: Text('Dropoff address is required. Please select a dropoff location on the map.'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 3),
        ),
      );
      setState(() => _activeStep = 1);
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (!_parcelPhotoUploaded && _parcelPhoto != null) {
        try {
          await _uploadParcelPhoto();
        } catch (e) {
          debugPrint('⚠️ Photo upload failed, but proceeding with booking: $e');
        }
      }

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
        packageDescription: null,
        itemDetails: _itemDetailsController.text.trim(),
        itemWeight: double.tryParse(_itemWeightController.text.trim()) ?? 0.0,
        itemQuantity: int.tryParse(_itemQuantityController.text.trim()) ?? 1,
        needsThermalBag: _needsThermalBag,
        needsAbono: _needsAbono,
        deliveryFee: _deliveryFee,
        parcelPhotoUrl: _parcelPhotoUrl,
      );
      
      if (!mounted) return;
      
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
  
  Widget _buildPhotoAndDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Parcel Photo & Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure that your parcel fits on a motorcycle',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Take a photo and provide details about your parcel',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            
            // Parcel Photo Section
            GestureDetector(
              onTap: _takeParcelPhoto,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.border.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                child: _parcelPhoto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_parcelPhoto!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, size: 64, color: AppColors.textSecondary),
                          const SizedBox(height: 16),
                          Text(
                            'Tap to take photo of parcel',
                            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
              ),
            ),
            
            if (_parcelPhoto != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _takeParcelPhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Retake Photo'),
              ),
            ],
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            // Package Details
            const Text(
              'Package Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemDetailsController,
              decoration: const InputDecoration(
                labelText: 'Details of Item *',
                hintText: 'Describe the item being sent',
                prefixIcon: Icon(Icons.inventory_2),
              ),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Item details are required' : null,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemWeightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Weight (kg)',
                hintText: 'e.g., 1.5',
                prefixIcon: Icon(Icons.scale),
              ),
              validator: (value) {
  if (value == null || value.trim().isEmpty) {
    return null; // ✅ optional
  }

  final weight = double.tryParse(value.trim());
  if (weight == null || weight <= 0) {
    return 'Please enter a valid weight';
  }

  return null;
},

            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _itemQuantityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantity *',
                hintText: 'e.g., 1',
                prefixIcon: Icon(Icons.numbers),
              ),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) return 'Quantity is required';
                final quantity = int.tryParse(value!.trim());
                if (quantity == null || quantity <= 0) return 'Please enter a valid quantity';
                return null;
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Thermal Bag'),
              subtitle: const Text('Keep items cool/warm during delivery'),
              value: _needsThermalBag,
              onChanged: (value) => setState(() => _needsThermalBag = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Abono (Cash on Delivery)'),
              subtitle: const Text('Additional ₱55.00 fee'),
              value: _needsAbono,
              onChanged: (value) {
                setState(() {
                  _needsAbono = value ?? false;
                  _calculateDeliveryFee();
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickupLocationStep() {
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select where the parcel will be picked up',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            
            _buildLocationSelector(
              label: 'Pickup Address',
              address: _pickupAddress,
              onTap: () => _openMapModal(true),
              isLoading: _isLoadingPickupLocation,
              accentColor: Colors.green.shade600,
              icon: Icons.location_on,
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
                  child: _isLoadingPickupLocation
                      ? Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Loading your location...', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        )
                      : Stack(
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
                                if (_pickupLatLng != null) {
                                  controller.animateCamera(
                                    CameraUpdate.newLatLngZoom(_pickupLatLng!, 16),
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
                                        'Tap to change location',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            
            // Sender Details
            const Text(
              'Sender Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text('*', style: TextStyle(fontSize: 20, color: AppColors.error, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select the dropoff location on the map (Required)',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                        style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            
            _buildLocationSelector(
              label: 'Dropoff Address',
              address: _dropoffAddress,
              onTap: () => _openMapModal(false),
              isLoading: false,
              accentColor: AppColors.primary,
              icon: Icons.flag,
            ),
            const SizedBox(height: 16),
            
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
                                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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
                            controller.animateCamera(CameraUpdate.newLatLngZoom(_dropoffLatLng!, 16));
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
                                Text('Tap to select location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    if (_deliveryFee == null && _pickupLatLng != null && _dropoffLatLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _calculateDeliveryFee());
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Confirm Delivery Details',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          if (_parcelPhoto != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Parcel Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_parcelPhoto!, height: 150, fit: BoxFit.cover),
                    ),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
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
                      const Text('Pickup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_pickupAddress ?? 'Not set'),
                  const SizedBox(height: 8),
                  Text('Sender: ${_senderNameController.text}'),
                  Text('Phone: ${_senderPhoneController.text}'),
                  if (_senderNotesController.text.trim().isNotEmpty)
                    Text('Notes: ${_senderNotesController.text.trim()}'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _activeStep = 0),
                        icon: const Icon(Icons.edit_location, size: 16),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                  if (_pickupLatLng != null)
                    Container(
                      height: 200,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(target: _pickupLatLng!, zoom: 16),
                          markers: {
                            Marker(
                              markerId: const MarkerId('pickup'),
                              position: _pickupLatLng!,
                              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                            ),
                          },
                          scrollGesturesEnabled: false,
                          zoomGesturesEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
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
                      const Text('Dropoff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.error)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_dropoffAddress ?? 'Not set'),
                  const SizedBox(height: 8),
                  Text('Recipient: ${_recipientNameController.text}'),
                  Text('Phone: ${_recipientPhoneController.text}'),
                  if (_recipientNotesController.text.trim().isNotEmpty)
                    Text('Notes: ${_recipientNotesController.text.trim()}'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _activeStep = 1),
                        icon: const Icon(Icons.edit_location, size: 16),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                  if (_dropoffLatLng != null)
                    Container(
                      height: 200,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(target: _dropoffLatLng!, zoom: 16),
                          markers: {
                            Marker(
                              markerId: const MarkerId('dropoff'),
                              position: _dropoffLatLng!,
                              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                            ),
                          },
                          scrollGesturesEnabled: false,
                          zoomGesturesEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Package Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildInfoRow('Item Details', _itemDetailsController.text.trim()),
                  _buildInfoRow('Weight', '${_itemWeightController.text.trim()} kg'),
                  _buildInfoRow('Quantity', _itemQuantityController.text.trim()),
                  if (_needsThermalBag)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: AppColors.success, size: 16),
                          const SizedBox(width: 8),
                          const Text('Thermal Bag Required'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Delivery Fee Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  
                  if (_distance != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Distance', style: TextStyle(color: AppColors.textSecondary)),
                        Text('${_distance!.toStringAsFixed(2)} km', style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Base Fee (First km)', style: TextStyle(color: AppColors.textSecondary)),
                      const Text('₱55.00', style: TextStyle(fontWeight: FontWeight.w500)),
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
                        Text('₱${((_distance! - 1.0) * 10.0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                  
                  if (_needsAbono) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Abono (Cash on Delivery)', style: TextStyle(color: AppColors.textSecondary)),
                        const Text('₱55.00', style: TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                  
                  const Divider(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Delivery Fee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(
                        _deliveryFee != null ? '₱${_deliveryFee!.toStringAsFixed(2)}' : 'Calculating...',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
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

Widget _buildLocationSelector({
  required String label,
  required String? address,
  required VoidCallback onTap,
  required bool isLoading,
  required Color accentColor,
  required IconData icon,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: isLoading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: address == null ? Colors.grey.shade400 : accentColor,
          width: 2,
        ),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (label.contains('Dropoff'))
                      Text(' *', style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                if (isLoading)
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Fetching location...',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                      ),
                    ],
                  )
                else
                  Text(
                    address ?? 'Tap to select location on map',
                    style: TextStyle(
                      fontSize: 15,
                      color: address == null ? Colors.grey.shade500 : Colors.black87,
                      fontWeight: address == null ? FontWeight.normal : FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!isLoading)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit_location_alt, color: Colors.white, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    'Change',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
            color: isActive || isCompleted ? AppColors.primary : AppColors.border,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive || isCompleted ? Colors.white : AppColors.textSecondary,
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
            color: isActive || isCompleted ? AppColors.primary : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Details'),
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
          Expanded(
            child: _activeStep == 0
                ? _buildPhotoAndDetailsStep()
                : _activeStep == 1
                    ? _buildPickupLocationStep()
                    : _activeStep == 2
                        ? _buildDropoffStep()
                        : _buildConfirmationStep(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_activeStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => setState(() => _activeStep--),
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
                                if (_parcelPhoto == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please take a photo of the parcel')),
                                  );
                                  return;
                                }
                                if (_formKey.currentState?.validate() ?? false) {
                                  setState(() => _activeStep++);
                                }
                              } else if (_activeStep == 1) {
                                if (_formKey.currentState?.validate() ?? false) {
                                  if (_pickupLatLng == null || _pickupAddress == null || _pickupAddress!.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please select a pickup location on the map'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => _activeStep++);
                                }
                              } else if (_activeStep == 2) {
                                if (_formKey.currentState?.validate() ?? false) {
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
                                  setState(() => _activeStep++);
                                }
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
}

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
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      // Check location service and permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable location services.');
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          throw Exception('Location permission is required to fetch your current location.');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was permanently denied. Please enable it in settings.');
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final newPosition = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedPosition = newPosition;
        _isFetchingLocation = false;
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(newPosition, 16),
      );
    } catch (e) {
      setState(() => _isFetchingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching location: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _selectedPosition, zoom: 16),
          markers: {
            Marker(
              markerId: const MarkerId('selected'),
              position: _selectedPosition,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                widget.isPickup ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
              ),
              draggable: true,
              onDragEnd: (newPosition) {
                setState(() => _selectedPosition = newPosition);
                _mapController?.animateCamera(
                  CameraUpdate.newLatLng(newPosition),
                );
              },
            ),
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          onMapCreated: (controller) => _mapController = controller,
          onTap: (latLng) => setState(() => _selectedPosition = latLng),
        ),
        Positioned(
          top: 100,
          left: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildZoomButton(Icons.add, () => _mapController?.animateCamera(CameraUpdate.zoomIn()), true),
              Container(width: 56, height: 2, color: Colors.grey[500]),
              _buildZoomButton(Icons.remove, () => _mapController?.animateCamera(CameraUpdate.zoomOut()), false),
            ],
          ),
        ),
        // Auto-fetch current location button (only for dropoff)
        if (!widget.isPickup)
          Positioned(
            top: 100,
            right: 16,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              elevation: 10,
              shadowColor: Colors.black87,
              child: InkWell(
                onTap: _isFetchingLocation ? null : _fetchCurrentLocation,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[700]!, width: 2.5),
                  ),
                  child: _isFetchingLocation
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, size: 28, color: Colors.black87),
                ),
              ),
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
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Text(
                  '💡 Tap anywhere on the map or drag the marker to set location',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => widget.onLocationSelected(_selectedPosition),
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap, bool isTop) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.only(
        topLeft: isTop ? const Radius.circular(8) : Radius.zero,
        topRight: isTop ? const Radius.circular(8) : Radius.zero,
        bottomLeft: !isTop ? const Radius.circular(8) : Radius.zero,
        bottomRight: !isTop ? const Radius.circular(8) : Radius.zero,
      ),
      elevation: 10,
      shadowColor: Colors.black87,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.only(
          topLeft: isTop ? const Radius.circular(8) : Radius.zero,
          topRight: isTop ? const Radius.circular(8) : Radius.zero,
          bottomLeft: !isTop ? const Radius.circular(8) : Radius.zero,
          bottomRight: !isTop ? const Radius.circular(8) : Radius.zero,
        ),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: isTop ? const Radius.circular(8) : Radius.zero,
              topRight: isTop ? const Radius.circular(8) : Radius.zero,
              bottomLeft: !isTop ? const Radius.circular(8) : Radius.zero,
              bottomRight: !isTop ? const Radius.circular(8) : Radius.zero,
            ),
            border: Border.all(color: Colors.grey[700]!, width: 2.5),
          ),
          child: Icon(icon, size: 32, color: Colors.black87),
        ),
      ),
    );
  }
}