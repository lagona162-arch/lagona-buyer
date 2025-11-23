import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/maps_config.dart';
import '../services/supabase_service.dart';
import 'merchant_list_page.dart';

class CustomerRegistrationPage extends StatefulWidget {
	static const String routeName = '/register';
	const CustomerRegistrationPage({super.key});

	@override
	State<CustomerRegistrationPage> createState() => _CustomerRegistrationPageState();
}

class _CustomerRegistrationPageState extends State<CustomerRegistrationPage> {
	final TextEditingController firstNameController = TextEditingController();
	final TextEditingController lastNameController = TextEditingController();
	final TextEditingController middleInitialController = TextEditingController();
	final TextEditingController phoneController = TextEditingController();
	final TextEditingController searchController = TextEditingController();

	List<Map<String, String>> predictions = [];
	LatLng? selectedLatLng;
	String? selectedAddress;
	GoogleMapController? mapController;
	final SupabaseService _supabase = SupabaseService();
	StreamSubscription<Position>? _posSub;
	bool _liveTracking = false;
	final _formKey = GlobalKey<FormState>();
	
	/// Updates the map camera to the current selected location
	Future<void> _updateMapCamera() async {
		if (mapController != null && selectedLatLng != null) {
			try {
				await mapController!.animateCamera(
					CameraUpdate.newLatLngZoom(selectedLatLng!, 17),
				);
			} catch (e) {
				debugPrint('Error updating map camera: $e');
			}
		}
	}

	@override
	void initState() {
		super.initState();
		_loadUserData();
	}
	
	@override
	void dispose() {
		_posSub?.cancel();
		firstNameController.dispose();
		lastNameController.dispose();
		middleInitialController.dispose();
		phoneController.dispose();
		searchController.dispose();
		super.dispose();
	}
	
	String? _validatePhoneNumber(String? value) {
		if (value == null || value.trim().isEmpty) {
			return 'Phone number is required';
		}
		
		// Remove spaces, dashes, parentheses, and + signs
		final cleaned = value.trim().replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
		
		// Check if it's a valid Philippines phone number
		// Format: 09XXXXXXXXX (11 digits starting with 09)
		final phPattern = RegExp(r'^09\d{9}$'); // 09XXXXXXXXX (11 digits)
		
		if (phPattern.hasMatch(cleaned)) {
			return null; // Valid: 09XXXXXXXXX
		}
		
		// Check if user entered +63 format and convert it
		if (cleaned.startsWith('639') && cleaned.length == 12) {
			// Convert +639XXXXXXXXX to 09XXXXXXXXX
			final converted = '0${cleaned.substring(2)}';
			if (phPattern.hasMatch(converted)) {
				phoneController.text = converted;
				return null;
			}
		}
		
		return 'Invalid phone number. Must be 11 digits starting with 09 (e.g., 09123456789)';
	}

	Future<void> _loadUserData() async {
		final user = Supabase.instance.client.auth.currentUser;
		if (user != null) {
			// Try to get name and phone from users table
			try {
				final response = await Supabase.instance.client
					.from('users')
					.select('firstname, lastname, middle_initial, phone')
					.eq('id', user.id)
					.single();
				
				if (response['firstname'] != null) {
					firstNameController.text = response['firstname'] as String;
				}
				if (response['lastname'] != null) {
					lastNameController.text = response['lastname'] as String;
				}
				if (response['middle_initial'] != null) {
					middleInitialController.text = response['middle_initial'] as String;
				}
				if (response['phone'] != null) {
					phoneController.text = response['phone'] as String;
				}
			} catch (_) {
				// User might not exist in users table yet, try metadata as fallback
				final fullName = user.userMetadata?['full_name'] as String?;
				if (fullName != null && fullName.isNotEmpty) {
					// Try to split full name (fallback)
					final parts = fullName.trim().split(' ');
					if (parts.isNotEmpty) {
						firstNameController.text = parts[0];
						if (parts.length > 1) {
							lastNameController.text = parts[parts.length - 1];
							if (parts.length > 2 && parts[1].length <= 2) {
								middleInitialController.text = parts[1].replaceAll('.', '').toUpperCase();
							}
						}
					}
				}
			}
		}
	}

	Future<void> fetchAutocomplete(String input) async {
		if (input.trim().isEmpty) {
			setState(() => predictions = []);
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
		final res = await http.get(uri);
		if (res.statusCode == 200) {
			final data = json.decode(res.body) as Map<String, dynamic>;
			final preds = (data['predictions'] as List)
				.map((p) => {
					'description': p['description'] as String,
					'place_id': p['place_id'] as String,
				})
				.toList();
			setState(() => predictions = preds);
		}
	}

	Future<void> selectPlace(String placeId, String description) async {
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
				selectedLatLng = LatLng(lat, lng);
				selectedAddress = data['result']['formatted_address'] as String? ?? description;
				searchController.text = selectedAddress!;
				predictions = [];
			});
			if (mapController != null) {
				await mapController!.animateCamera(
					CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
				);
			}
		}
	}

	Future<void> _reverseGeocode(LatLng latLng) async {
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
				// Show address with coordinates
				final addressWithCoords = address != null
					? '$address (${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)})'
					: '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
				
				if (!mounted) return;
				setState(() {
					selectedAddress = address ?? '${latLng.latitude}, ${latLng.longitude}';
					searchController.text = addressWithCoords;
				});
			} else {
				// No address found, just show coordinates
				if (!mounted) return;
				final coords = '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
				setState(() {
					selectedAddress = coords;
					searchController.text = coords;
				});
			}
		} else {
			// If geocoding fails, still set coordinates
			if (!mounted) return;
			final coords = '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
			setState(() {
				selectedAddress = coords;
				searchController.text = coords;
			});
		}
	}

	Future<void> _toggleLiveLocation() async {
		if (_liveTracking) {
			await _posSub?.cancel();
			setState(() => _liveTracking = false);
			return;
		}
		
		// Check location service first
		bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
		if (!serviceEnabled) {
			if (!mounted) return;
			final shouldOpen = await showDialog<bool>(
				context: context,
				builder: (context) => AlertDialog(
					title: const Text('Location Services Disabled'),
					content: const Text('Please enable location services to use this feature.'),
					actions: [
						TextButton(
							onPressed: () => Navigator.of(context).pop(false),
							child: const Text('Cancel'),
						),
						TextButton(
							onPressed: () => Navigator.of(context).pop(true),
							child: const Text('Open Settings'),
						),
					],
				),
			);
			if (shouldOpen == true) {
				await Geolocator.openLocationSettings();
			}
			return;
		}
		
		// Check and request permission only if needed
		LocationPermission permission = await Geolocator.checkPermission();
		if (permission == LocationPermission.denied) {
			permission = await Geolocator.requestPermission();
			if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
				if (!mounted) return;
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(content: Text('Location permission is required to use this feature')),
				);
				return;
			}
		}
		if (permission == LocationPermission.deniedForever) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Location permission was permanently denied. Please enable it in settings.'),
					duration: Duration(seconds: 3),
				),
			);
			return;
		}
		
		// Get current position immediately (not just from stream)
		try {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Getting your location...'),
					duration: Duration(seconds: 2),
				),
			);
			
			final Position currentPos = await Geolocator.getCurrentPosition(
				desiredAccuracy: LocationAccuracy.high,
			);
			
			final latLng = LatLng(currentPos.latitude, currentPos.longitude);
			if (!mounted) return;
			
			setState(() {
				selectedLatLng = latLng;
				_liveTracking = true;
			});
			
			// Update map immediately - wait a bit for state to update
			await Future.delayed(const Duration(milliseconds: 100));
			await _updateMapCamera();
			
			// Get address for current location
			await _reverseGeocode(latLng);
			
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Location found!'),
					duration: Duration(seconds: 1),
				),
			);
		} catch (e) {
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(
					content: Text('Failed to get location: $e'),
					backgroundColor: Colors.red,
				),
			);
			return;
		}
		
		// Start position stream for live tracking
		_posSub = Geolocator.getPositionStream(
			locationSettings: const LocationSettings(
				accuracy: LocationAccuracy.high,
				distanceFilter: 10, // Update every 10 meters
			),
		).listen((pos) async {
			if (!mounted) return;
			final latLng = LatLng(pos.latitude, pos.longitude);
			setState(() {
				selectedLatLng = latLng;
			});
			if (mapController != null) {
				await mapController!.animateCamera(
					CameraUpdate.newLatLngZoom(latLng, 17),
				);
			}
			// Update address periodically
			await _reverseGeocode(latLng);
		});
	}

	Future<void> submit() async {
		// Validate form first
		if (!_formKey.currentState!.validate()) {
			return;
		}
		
		if (selectedLatLng == null || selectedAddress == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Please select an address on the map or use your current location')),
			);
			return;
		}
		
		// Clean phone number (remove spaces, dashes, etc.)
		final phone = phoneController.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
		final user = Supabase.instance.client.auth.currentUser;
		if (user != null) {
			try {
				await _supabase.updateCustomerAddress(
					customerId: user.id,
					address: selectedAddress!,
					latitude: selectedLatLng!.latitude,
					longitude: selectedLatLng!.longitude,
					phone: phone, // Use cleaned phone number
					firstName: firstNameController.text.trim(),
					lastName: lastNameController.text.trim(),
					middleInitial: middleInitialController.text.trim().isNotEmpty
						? middleInitialController.text.trim().toUpperCase()
						: null,
				);
				if (mounted) {
					Navigator.of(context).pushReplacementNamed(MerchantListPage.routeName);
				}
			} catch (e) {
				if (mounted) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(
							content: Text('Registration failed: ${e.toString()}'),
							backgroundColor: Colors.red,
						),
					);
				}
			}
		}
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Customer Registration')),
			body: Column(
				children: [
					Padding(
						padding: const EdgeInsets.all(12),
						child: Form(
							key: _formKey,
							child: Column(
								children: [
								TextFormField(
									controller: firstNameController,
									enabled: false, // Read-only, set from previous page
									decoration: InputDecoration(
										labelText: 'First Name',
										border: const OutlineInputBorder(),
										filled: true,
										fillColor: Colors.grey.shade100,
									),
								),
								const SizedBox(height: 12),
								TextField(
									controller: middleInitialController,
									textInputAction: TextInputAction.next,
									maxLength: 1,
									textCapitalization: TextCapitalization.characters,
									decoration: const InputDecoration(
										labelText: 'Middle Initial (Optional)',
										border: OutlineInputBorder(),
										counterText: '',
									),
								),
								const SizedBox(height: 12),
								TextFormField(
									controller: lastNameController,
									enabled: false, // Read-only, set from previous page
									decoration: InputDecoration(
										labelText: 'Last Name',
										border: const OutlineInputBorder(),
										filled: true,
										fillColor: Colors.grey.shade100,
									),
								),
								const SizedBox(height: 12),
								TextFormField(
									controller: phoneController,
									keyboardType: TextInputType.phone,
									textInputAction: TextInputAction.next,
									maxLength: 11, // Limit to 11 digits for PH format (09XXXXXXXXX)
									decoration: InputDecoration(
										labelText: 'Phone Number',
										hintText: '09XXXXXXXXX',
										border: const OutlineInputBorder(),
										helperText: 'Philippines: 11 digits starting with 09',
										counterText: '', // Hide character counter
									),
									validator: _validatePhoneNumber,
								),
								const SizedBox(height: 12),
								TextField(
									controller: searchController,
									onChanged: fetchAutocomplete,
									decoration: const InputDecoration(
										labelText: 'Search Address',
										hintText: 'Street, barangay, city',
										border: OutlineInputBorder(),
									),
								),
								if (predictions.isNotEmpty)
									Container(
										margin: const EdgeInsets.only(top: 8),
										decoration: BoxDecoration(
											border: Border.all(color: Colors.grey.shade300),
											borderRadius: BorderRadius.circular(8),
											color: Colors.white,
										),
										constraints: const BoxConstraints(maxHeight: 200),
										child: ListView.builder(
											itemCount: predictions.length,
											itemBuilder: (context, index) {
												final p = predictions[index];
												return ListTile(
													title: Text(p['description']!),
													onTap: () => selectPlace(p['place_id']!, p['description']!),
												);
											},
										),
									),
								],
							),
						),
					),
					Expanded(
						child: GoogleMap(
							key: ValueKey(
								'${selectedLatLng?.latitude ?? 0}_${selectedLatLng?.longitude ?? 0}_$_liveTracking',
							),
							initialCameraPosition: CameraPosition(
								target: selectedLatLng ?? const LatLng(14.5995, 120.9842),
								zoom: selectedLatLng != null ? 17 : 12,
							),
							onMapCreated: (GoogleMapController controller) async {
								mapController = controller;
								// Move camera to selected location if available
								if (selectedLatLng != null) {
									// Wait a bit for map to fully initialize
									await Future.delayed(const Duration(milliseconds: 300));
									await _updateMapCamera();
								}
							},
							markers: {
								if (selectedLatLng != null)
									Marker(
										markerId: const MarkerId('selected'),
										position: selectedLatLng!,
										draggable: true,
										onDragEnd: (pos) {
											setState(() {
												selectedLatLng = pos;
												_liveTracking = false;
												_posSub?.cancel();
											});
											_reverseGeocode(pos);
										},
									),
							},
							onTap: (pos) {
								setState(() {
									selectedLatLng = pos;
									_liveTracking = false;
									_posSub?.cancel();
								});
								_reverseGeocode(pos);
							},
							myLocationButtonEnabled: true,
							myLocationEnabled: _liveTracking,
							mapType: MapType.normal,
							zoomControlsEnabled: true,
							compassEnabled: true,
						),
					),
					SafeArea(
						child: Padding(
							padding: const EdgeInsets.all(12),
							child: SizedBox(
								width: double.infinity,
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.stretch,
									children: [
										OutlinedButton.icon(
											onPressed: _toggleLiveLocation,
											icon: Icon(_liveTracking ? Icons.gps_off : Icons.gps_fixed),
											label: Text(_liveTracking ? 'Stop using my live location' : 'Use my current location'),
										),
										const SizedBox(height: 8),
										ElevatedButton(
											onPressed: submit,
											child: const Text('Confirm & Register'),
										),
									],
								),
							),
						),
					),
				],
			),
		);
	}
}


