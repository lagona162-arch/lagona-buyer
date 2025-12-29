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
import 'service_selection_page.dart';

class CustomerRegistrationPage extends StatefulWidget {
	static const String routeName = '/register';
	final String? userId; // User ID from registration
	final bool isEditMode; // True if editing existing address, false for new registration
	
	const CustomerRegistrationPage({
		super.key, 
		this.userId,
		this.isEditMode = false,
	});

	@override
	State<CustomerRegistrationPage> createState() => _CustomerRegistrationPageState();
}

class _CustomerRegistrationPageState extends State<CustomerRegistrationPage> {
	final TextEditingController phoneController = TextEditingController();
	final TextEditingController searchController = TextEditingController();

	LatLng? selectedLatLng;
	String? selectedAddress;
	GoogleMapController? mapController;
	final SupabaseService _supabase = SupabaseService();
	StreamSubscription<Position>? _posSub;
	bool _liveTracking = false;
	final _formKey = GlobalKey<FormState>();
	String? _userId; // Store user ID
	
	
	Future<void> _updateMapCamera() async {
		if (mapController != null && selectedLatLng != null && mounted) {
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
		// Get user ID from widget parameter or from auth
		_userId = widget.userId;
		_loadUserData();
		_checkAuthState();
	}
	
	Future<void> _checkAuthState() async {
		// Check if user exists, if not, try to get from session
		final user = Supabase.instance.client.auth.currentUser;
		if (user == null) {
			// Try to get the session
			final session = Supabase.instance.client.auth.currentSession;
			debugPrint('Current session: $session');
			debugPrint('Current user: $user');
			
			// Try refreshing the session to get the user
			try {
				final refreshedSession = await Supabase.instance.client.auth.refreshSession();
				debugPrint('Refreshed session user: ${refreshedSession.user?.id}');
			} catch (e) {
				debugPrint('Could not refresh session: $e');
			}
		} else {
			debugPrint('User found in initState: ${user.id}, email confirmed: ${user.emailConfirmedAt != null}');
		}
	}
	
	@override
	void dispose() {
		_posSub?.cancel();
		phoneController.dispose();
		searchController.dispose();
		mapController?.dispose();
		super.dispose();
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
				phoneController.text = converted;
				return null;
			}
		}
		
		return 'Invalid phone number. Must be 11 digits starting with 09 (e.g., 09123456789)';
	}

	Future<void> _loadUserData() async {
		// Only load phone number if it exists, don't pre-fill name fields
		// Names should be entered fresh or come from the registration page
		final user = Supabase.instance.client.auth.currentUser;
		if (user != null) {
			try {
				final response = await Supabase.instance.client
					.from('users')
					.select('phone')
					.eq('id', user.id)
					.single();
				
				// Only pre-fill phone if it exists
				if (response['phone'] != null) {
					phoneController.text = response['phone'] as String;
				}
				
				// If in edit mode, also load existing address
				if (widget.isEditMode) {
					try {
						final customerData = await Supabase.instance.client
							.from('customers')
							.select('address, latitude, longitude')
							.eq('id', user.id)
							.maybeSingle();
						
						if (customerData != null) {
							if (customerData['latitude'] != null && customerData['longitude'] != null) {
								selectedLatLng = LatLng(
									(customerData['latitude'] as num).toDouble(),
									(customerData['longitude'] as num).toDouble(),
								);
								selectedAddress = customerData['address'] as String?;
								searchController.text = selectedAddress ?? '';
								
								// Update map camera after a short delay to ensure map is ready
								Future.delayed(const Duration(milliseconds: 500), () {
									_updateMapCamera();
								});
							}
						}
					} catch (e) {
						debugPrint('Error loading customer address: $e');
					}
				}
			} catch (_) {
				// No user data found, that's okay - user will enter everything fresh
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
				
				if (!mounted) return;
				setState(() {
					selectedAddress = address ?? '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
					searchController.text = selectedAddress!;
				});
			} else {
				if (!mounted) return;
				final coords = '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
				setState(() {
					selectedAddress = coords;
					searchController.text = coords;
				});
			}
		} else {
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
			_posSub = null;
			setState(() => _liveTracking = false);
			return;
		}
		
		
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
			
			
			await Future.delayed(const Duration(milliseconds: 100));
			await _updateMapCamera();
			
			
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
		
		
		_posSub = Geolocator.getPositionStream(
			locationSettings: const LocationSettings(
				accuracy: LocationAccuracy.high,
				distanceFilter: 10, 
			),
		).listen((pos) {
			// CRITICAL: Check live tracking flag FIRST - must be synchronous check
			// Don't use async/await here to avoid delays
			if (!mounted || !_liveTracking || _posSub == null) {
				return; // Stop immediately if live tracking is disabled
			}
			
			final latLng = LatLng(pos.latitude, pos.longitude);
			
			// Double-check flag before updating (race condition protection)
			if (!_liveTracking) return;
			
			setState(() {
				selectedLatLng = latLng;
			});
			
			// Update camera asynchronously (non-blocking)
			if (mapController != null) {
				mapController!.animateCamera(
					CameraUpdate.newLatLngZoom(latLng, 17),
				).catchError((e) {
					debugPrint('Error animating camera in live tracking: $e');
				});
			}
			
			// Reverse geocode asynchronously (non-blocking)
			_reverseGeocode(latLng);
		});
	}

	Future<void> submit() async {
		debugPrint('=== Submit button clicked ===');
		debugPrint('selectedLatLng: $selectedLatLng');
		debugPrint('selectedAddress: $selectedAddress');
		
		if (!_formKey.currentState!.validate()) {
			debugPrint('Form validation failed');
			return;
		}
		
		if (selectedLatLng == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Please select a location on the map or use your current location')),
			);
			return;
		}
		
		// Use coordinates as fallback if address is still null
		final address = selectedAddress ?? '${selectedLatLng!.latitude.toStringAsFixed(6)}, ${selectedLatLng!.longitude.toStringAsFixed(6)}';
		
		final phone = phoneController.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
		
		// Get user ID - prefer widget parameter, then try auth
		String? userId = _userId;
		
		// If in edit mode, always use current authenticated user
		if (widget.isEditMode) {
			final user = Supabase.instance.client.auth.currentUser;
			if (user == null) {
				debugPrint('No authenticated user found in edit mode');
				ScaffoldMessenger.of(context).showSnackBar(
					const SnackBar(
						content: Text('Please log in to edit your address'),
						backgroundColor: Colors.red,
						duration: Duration(seconds: 3),
					),
				);
				return;
			}
			userId = user.id;
		} else if (userId == null) {
			// Try to get from auth (for new registration flow)
			var user = Supabase.instance.client.auth.currentUser;
			if (user == null) {
				final session = Supabase.instance.client.auth.currentSession;
				if (session?.user != null) {
					user = session!.user;
					debugPrint('Got user from session: ${user.id}');
				}
			}
			
			if (user == null) {
				// Try refreshing the session
				try {
					final refreshedSession = await Supabase.instance.client.auth.refreshSession();
					user = refreshedSession.user;
					debugPrint('Got user from refreshed session: ${user?.id}');
				} catch (e) {
					debugPrint('Error refreshing session: $e');
				}
			}
			
			userId = user?.id;
		}
		
		if (userId == null) {
			debugPrint('No user ID found - user needs to verify email or log in');
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(
					content: Text('Please verify your email first, or log in if you already have an account'),
					duration: Duration(seconds: 5),
				),
			);
			return;
		}
		
		try {
			debugPrint('Updating customer address...');
			debugPrint('Using user ID: $userId');
			await _supabase.updateCustomerAddress(
				customerId: userId,
				address: address,
				latitude: selectedLatLng!.latitude,
				longitude: selectedLatLng!.longitude,
				phone: phone,
			);
			debugPrint('✅ Customer address updated successfully');
			
			if (mounted) {
				if (widget.isEditMode) {
					// For edit mode, just show success and go back
					ScaffoldMessenger.of(context).showSnackBar(
						const SnackBar(
							content: Text('Address updated successfully!'),
							backgroundColor: Colors.green,
							duration: Duration(seconds: 2),
						),
					);
					Navigator.of(context).pop();
				} else {
					// For new registration, show success message and redirect to login
					ScaffoldMessenger.of(context).showSnackBar(
						const SnackBar(
							content: Text('Registration complete! Please verify your email and log in.'),
							backgroundColor: Colors.green,
							duration: Duration(seconds: 3),
						),
					);
					
					// Navigate to login page since user needs to verify email first
					Navigator.of(context).pushNamedAndRemoveUntil(
						'/login',
						(route) => false, // Remove all previous routes
					);
				}
			}
		} catch (e, stackTrace) {
			debugPrint('❌ Registration failed: $e');
			debugPrint('Stack trace: $stackTrace');
			if (mounted) {
				ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(
						content: Text('Registration failed: ${e.toString()}'),
						backgroundColor: Colors.red,
						duration: const Duration(seconds: 5),
					),
				);
			}
		}
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(
				title: Text(widget.isEditMode ? 'Edit Address' : 'Customer Registration'),
			),
			body: Column(
				children: [
					Padding(
						padding: const EdgeInsets.all(12),
						child: Form(
							key: _formKey,
							child: Column(
								children: [
								TextFormField(
									controller: phoneController,
									keyboardType: TextInputType.phone,
									textInputAction: TextInputAction.next,
									maxLength: 11, 
									decoration: InputDecoration(
										labelText: 'Phone Number',
										hintText: '09XXXXXXXXX',
										border: const OutlineInputBorder(),
										helperText: 'Philippines: 11 digits starting with 09',
										counterText: '', 
									),
									validator: _validatePhoneNumber,
								),
								const SizedBox(height: 12),
								// Address display field (read-only, shows selected address)
								TextFormField(
									controller: searchController,
									readOnly: true,
									decoration: InputDecoration(
										labelText: 'Selected Address',
										hintText: 'Tap on the map or use current location',
										border: const OutlineInputBorder(),
										prefixIcon: const Icon(Icons.location_on),
										filled: true,
										fillColor: selectedAddress != null ? Colors.green.shade50 : Colors.grey.shade100,
										helperText: selectedAddress != null 
											? 'Address selected ✓' 
											: 'Tap anywhere on the map below to select your location',
									),
									validator: (value) {
										if (selectedLatLng == null || selectedAddress == null) {
											return 'Please select a location on the map';
										}
										return null;
									},
								),
								],
							),
						),
					),
					Expanded(
						child: Stack(
							children: [
								GoogleMap(
									initialCameraPosition: CameraPosition(
										target: selectedLatLng ?? const LatLng(14.5995, 120.9842),
										zoom: selectedLatLng != null ? 17 : 12,
									),
									onMapCreated: (GoogleMapController controller) {
										mapController = controller;
										if (selectedLatLng != null) {
											// Update camera after map is created
											WidgetsBinding.instance.addPostFrameCallback((_) async {
												if (mounted && mapController != null && selectedLatLng != null) {
													await mapController!.animateCamera(
														CameraUpdate.newLatLngZoom(selectedLatLng!, 17),
													);
												}
											});
										}
									},
									markers: selectedLatLng != null
										? {
											Marker(
												markerId: const MarkerId('selected'),
												position: selectedLatLng!,
												draggable: true,
												icon: BitmapDescriptor.defaultMarkerWithHue(
													BitmapDescriptor.hueRed,
												),
												onDragEnd: (pos) async {
													if (!mounted) return;
													
													// IMMEDIATELY stop live tracking - cancel subscription and set flag FIRST
													if (_liveTracking) {
														_liveTracking = false; // Set flag immediately to prevent stream updates
														await _posSub?.cancel();
														_posSub = null;
													}
													
													// Set coordinates as fallback address immediately
													final coords = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
													
													setState(() {
														selectedLatLng = pos;
														selectedAddress = coords; // Set fallback immediately
														searchController.text = coords;
													});
													
													// Update camera immediately
													if (mapController != null) {
														try {
															await mapController!.animateCamera(
																CameraUpdate.newLatLngZoom(pos, 17),
															);
														} catch (e) {
															debugPrint('Error animating camera: $e');
														}
													}
													
													// Then reverse geocode (non-blocking, will update address when done)
													_reverseGeocode(pos);
												},
											),
										}
										: {},
									onTap: (pos) async {
										if (!mounted) return;
										
										// IMMEDIATELY stop live tracking - cancel subscription and set flag FIRST
										if (_liveTracking) {
											_liveTracking = false; // Set flag immediately to prevent stream updates
											await _posSub?.cancel();
											_posSub = null;
										}
										
										// Set coordinates as fallback address immediately
										final coords = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
										
										// Update state with new location - always works, no delay
										setState(() {
											selectedLatLng = pos;
											selectedAddress = coords; // Set fallback immediately
											searchController.text = coords;
										});
										
										// Update camera immediately to show the marker
										if (mapController != null) {
											try {
												await mapController!.animateCamera(
													CameraUpdate.newLatLngZoom(pos, 17),
												);
											} catch (e) {
												debugPrint('Error animating camera: $e');
											}
										}
										
										// Then reverse geocode (non-blocking, will update address when done)
										_reverseGeocode(pos);
									},
									myLocationButtonEnabled: true,
									myLocationEnabled: true,
									mapType: MapType.normal,
									zoomControlsEnabled: true,
									compassEnabled: true,
									zoomGesturesEnabled: true,
									scrollGesturesEnabled: true,
									rotateGesturesEnabled: true,
									tiltGesturesEnabled: true,
								),
								// Instruction overlay
								if (selectedLatLng == null)
									Positioned(
										top: 16,
										left: 16,
										right: 16,
										child: Container(
											padding: const EdgeInsets.all(12),
											decoration: BoxDecoration(
												color: Colors.white,
												borderRadius: BorderRadius.circular(8),
												boxShadow: [
													BoxShadow(
														color: Colors.black.withOpacity(0.2),
														blurRadius: 8,
														offset: const Offset(0, 2),
													),
												],
											),
											child: Row(
												children: [
													Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
													const SizedBox(width: 8),
													Expanded(
														child: Text(
															'💡 Tap anywhere on the map or drag the marker to select your location',
															style: TextStyle(
																fontSize: 12,
																color: Colors.grey[800],
															),
														),
													),
												],
											),
										),
									),
							],
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
										ElevatedButton.icon(
											onPressed: _toggleLiveLocation,
											icon: Icon(_liveTracking ? Icons.gps_off : Icons.my_location),
											label: Text(_liveTracking ? 'Stop Live Tracking' : 'Use My Current Location'),
											style: ElevatedButton.styleFrom(
												backgroundColor: _liveTracking ? Colors.orange : Colors.blue,
												foregroundColor: Colors.white,
											),
										),
										const SizedBox(height: 8),
										ElevatedButton(
											onPressed: submit,
											style: ElevatedButton.styleFrom(
												backgroundColor: Colors.green,
												foregroundColor: Colors.white,
												padding: const EdgeInsets.symmetric(vertical: 16),
											),
											child: const Text(
												'Confirm & Register',
												style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
											),
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


