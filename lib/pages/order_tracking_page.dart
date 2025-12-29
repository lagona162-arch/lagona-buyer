import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../config/maps_config.dart';

class OrderTrackingPage extends StatefulWidget {
  static const String routeName = '/tracking';
  final String? orderId;
  const OrderTrackingPage({super.key, this.orderId});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  GoogleMapController? mapController;
  final SupabaseService _supabaseService = SupabaseService();
  
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  Map<String, dynamic>? _delivery;
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  LatLng? _riderLocation;
  LatLng? _userLocation;
  Timer? _updateTimer;
  Timer? _paymentStatusTimer;
  bool _isLoading = true;
  String? _errorMessage;
  List<LatLng>? _routePoints;
  final ImagePicker _imagePicker = ImagePicker();
  
  int? _etaSeconds;
  DateTime? _estimatedArrival;
  String _etaText = 'Calculating...';
  Timer? _etaTimer;
  
  bool _paymentRequestShown = false;
  bool _hasSubmittedPayment = false;
  bool _isPaymentApproved = false;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) {
      _loadDelivery();
      _getUserLocation();
      _checkPaymentStatus();
      _startPolling();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No delivery ID provided';
      });
    }
  }
  
  void _startPolling() {
    _updateTimer?.cancel();
    final status = _delivery?['status']?.toString().toLowerCase() ?? 'pending';
    final hasRider = _delivery?['rider_id'] != null ?? false;
    final paymentRequested = _delivery?['payment_requested'] == true;
    final needsFastPolling = status == 'pending' || 
                            (status == 'accepted' && (!hasRider || (hasRider && !paymentRequested && !_hasSubmittedPayment)));
    final interval = needsFastPolling ? const Duration(seconds: 3) : const Duration(seconds: 10);
    
    _updateTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      _loadDelivery();
      _getUserLocation();
    });
    
    _startPaymentStatusPolling();
  }
  
  void _startPaymentStatusPolling() {
    _paymentStatusTimer?.cancel();
    
    if (_hasSubmittedPayment && !_isPaymentApproved) {
      _paymentStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!mounted) return;
        await _checkPaymentStatus();
        
        if (_isPaymentApproved) {
          _paymentStatusTimer?.cancel();
          _loadDelivery();
        }
      });
    } else {
      _paymentStatusTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _etaTimer?.cancel();
    _paymentStatusTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadDelivery() async {
    if (widget.orderId == null) return;

    try {
      final delivery = await _supabaseService.getDeliveryById(widget.orderId!);
      
      if (delivery == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Delivery not found';
          });
        }
        return;
      }

      
      final pickupLat = delivery['pickup_latitude'] as double?;
      final pickupLng = delivery['pickup_longitude'] as double?;
      final dropoffLat = delivery['dropoff_latitude'] as double?;
      final dropoffLng = delivery['dropoff_longitude'] as double?;

      LatLng? pickup;
      LatLng? dropoff;
      LatLng? rider;

      if (pickupLat != null && pickupLng != null) {
        pickup = LatLng(pickupLat, pickupLng);
      }

      if (dropoffLat != null && dropoffLng != null) {
        dropoff = LatLng(dropoffLat, dropoffLng);
      }

      
      if (delivery['rider_id'] != null && delivery['riders'] != null) {
        final riderData = delivery['riders'] as Map<String, dynamic>;
        final riderLat = riderData['latitude'] as double?;
        final riderLng = riderData['longitude'] as double?;
        if (riderLat != null && riderLng != null) {
          rider = LatLng(riderLat, riderLng);
        }
      }

      
      final deliveryStatus = delivery['status']?.toString().toLowerCase() ?? '';
      final previousStatus = _delivery?['status']?.toString().toLowerCase() ?? '';
      final hasRider = delivery['rider_id'] != null;
      final paymentRequested = delivery['payment_requested'] == true;
      final previousPaymentRequested = _delivery?['payment_requested'] == true;
      
      
      
      await _checkPaymentStatus();
      
      
      if (paymentRequested && 
          !previousPaymentRequested && 
          !_hasSubmittedPayment && 
          !_paymentRequestShown && 
          mounted) {
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hasSubmittedPayment) {
            _showPaymentDialog();
          }
        });
      }

      final bool riderLocationChanged = rider != null && 
          (_riderLocation == null || 
           (rider.latitude != _riderLocation!.latitude || 
            rider.longitude != _riderLocation!.longitude));

      if (mounted) {
        setState(() {
          _delivery = delivery;
          _pickupLocation = pickup;
          _dropoffLocation = dropoff;
          _riderLocation = rider;
          _isLoading = false;
        });
        
        
        if (previousStatus != deliveryStatus) {
          _startPolling();
        }
        if (_isPaymentApproved) {
          _updateMarkers();
          
          
          if (pickup != null && dropoff != null && _routePoints == null) {
            await _fetchRoute(pickup, dropoff);
          } else {
            _updatePolylines();
          }
          
          
          
          final etaDestination = _userLocation ?? dropoff;
          
          if (rider != null && etaDestination != null) {
            
            if (riderLocationChanged || _estimatedArrival == null || _userLocation != null) {
              await _fetchRouteForETA(rider, etaDestination);
            }
            
            _etaTimer?.cancel();
            _etaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
              if (mounted && _estimatedArrival != null && _isPaymentApproved) {
                setState(() {
                  
                });
              }
              
              
              if (mounted && rider != null && _isPaymentApproved) {
                final destination = _userLocation ?? dropoff;
                if (destination != null) {
                  _fetchRouteForETA(rider, destination);
                }
              }
            });
          } else {
            
            _etaTimer?.cancel();
            if (mounted) {
              setState(() {
                _etaText = 'Calculating...';
                _estimatedArrival = null;
              });
            }
          }
          
          _updateCamera();
        } else {
          
          setState(() {
            _markers = {};
            _polylines = {};
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading delivery: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load delivery: $e';
        });
      }
    }
  }

  Future<void> _checkPaymentStatus() async {
    if (widget.orderId == null) return;
    
    try {
      
      
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      
      final payments = await Supabase.instance.client
          .from('payments')
          .select('id, status')
          .eq('delivery_id', widget.orderId!)
          .eq('customer_id', user.id)
          .order('created_at', ascending: false)
          .limit(1);
      
      
      final deliveryStatus = _delivery?['status']?.toString().toLowerCase().trim() ?? '';
      final deliveryIndicatesApproval = deliveryStatus == 'prepared' || 
                                        deliveryStatus == 'ready' ||
                                        deliveryStatus == 'assigned' ||
                                        deliveryStatus == 'picked_up' ||
                                        deliveryStatus == 'picked up' ||
                                        deliveryStatus == 'in_transit' ||
                                        deliveryStatus == 'in transit' ||
                                        deliveryStatus == 'on_the_way' ||
                                        deliveryStatus == 'on the way' ||
                                        deliveryStatus == 'delivered' ||
                                        deliveryStatus == 'completed';
      
      bool isApproved = false;
      String paymentStatus = '';
      
      if (payments.isNotEmpty) {
        final payment = payments[0];
        paymentStatus = payment['status']?.toString().toLowerCase() ?? '';
        
        
        
        isApproved = paymentStatus == 'verified' ||
                    paymentStatus == 'approved' || 
                    paymentStatus == 'confirmed' ||
                    deliveryIndicatesApproval;
        
      } else if (deliveryIndicatesApproval) {
        
        isApproved = true;
      }
      
      final wasApproved = _isPaymentApproved;
      setState(() {
        if (payments.isNotEmpty || deliveryIndicatesApproval) {
          _hasSubmittedPayment = true;
          _paymentRequestShown = true;
        }
        _isPaymentApproved = isApproved;
      });
      
      
      if (isApproved && !wasApproved) {
        debugPrint('🎉 Payment approved! Reloading delivery...');
        _paymentStatusTimer?.cancel(); 
        _loadDelivery(); 
        _startPolling(); 
      } else if (!isApproved && _hasSubmittedPayment) {
        
        _startPaymentStatusPolling();
      }
    } catch (e) {
      debugPrint('Error checking payment status: $e');
    }
  }

  Future<void> _getUserLocation() async {
    if (!_isPaymentApproved) return;
    
    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted && _isPaymentApproved) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });
        _updateMarkers();
        _updateCamera();
      }
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  void _updateMarkers() {
    if (!_isPaymentApproved) {
      setState(() {
        _markers = {};
      });
      return;
    }
    
    final markers = <Marker>{};

    
    if (_pickupLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'Pickup Location',
            snippet: _delivery?['pickup_address'] as String?,
          ),
        ),
      );
    }

    
    if (_dropoffLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: _dropoffLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Delivery Location',
            snippet: _delivery?['dropoff_address'] as String?,
          ),
        ),
      );
    }

    
    if (_riderLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: _riderLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(
            title: 'Rider',
            snippet: 'Your delivery rider',
          ),
        ),
      );
    }

    
    if (_userLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: _userLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Current position',
          ),
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    try {
      final apiKey = MapsConfig.apiKey;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=$apiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polyline = route['overview_polyline']['points'] as String;
          setState(() {
            _routePoints = _decodePolyline(polyline);
          });
          _updatePolylines();
          
          
          final legs = route['legs'] as List;
          if (legs.isNotEmpty && _riderLocation != null && _dropoffLocation != null) {
            final leg = legs[0];
            final duration = leg['duration'] as Map<String, dynamic>;
            final durationInSeconds = duration['value'] as int;
            final durationText = duration['text'] as String;
            
            final estimatedArrival = DateTime.now().add(Duration(seconds: durationInSeconds));
            setState(() {
              _etaSeconds = durationInSeconds;
              _estimatedArrival = estimatedArrival;
              _etaText = durationText;
            });
            debugPrint('✅ ETA extracted from route: $_etaText');
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
      
      setState(() {
        _routePoints = null;
      });
      _updatePolylines();
    }
  }

  
  Future<void> _fetchRouteForETA(LatLng origin, LatLng destination) async {
    try {
      debugPrint('=== Fetching ETA Route ===');
      debugPrint('Origin: ${origin.latitude}, ${origin.longitude}');
      debugPrint('Destination: ${destination.latitude}, ${destination.longitude}');
      
      
      if (origin.latitude.abs() > 90 || origin.longitude.abs() > 180 ||
          destination.latitude.abs() > 90 || destination.longitude.abs() > 180) {
        debugPrint('❌ Invalid coordinates detected');
        if (mounted) {
          setState(() {
            _etaText = 'Invalid location';
          });
        }
        return;
      }
      
      
      final distance = _calculateDistance(
        origin.latitude, 
        origin.longitude, 
        destination.latitude, 
        destination.longitude
      );
      
      debugPrint('Distance between rider and destination: ${distance.toStringAsFixed(3)} km');
      
      
      if (distance > 1000) {
        debugPrint('⚠️ Distance seems too large (${distance.toStringAsFixed(2)} km), coordinates may be invalid');
        if (mounted) {
          setState(() {
            _etaText = 'Unable to calculate';
          });
        }
        return;
      }
      
      
      
      final deliveryStatus = _delivery?['status']?.toString().toLowerCase() ?? '';
      final isDelivered = deliveryStatus == 'delivered' || deliveryStatus == 'completed';
      
      
      if (distance < 0.1 && isDelivered) { 
        debugPrint('✅ Rider is very close and delivery is completed');
        if (mounted) {
          setState(() {
            _etaSeconds = 0;
            _estimatedArrival = DateTime.now();
            _etaText = 'Arrived';
          });
        }
        return;
      }
      
      
      if (distance < 0.1) {
        debugPrint('⚠️ Rider is very close (<100m) but delivery is still in transit');
        if (mounted) {
          setState(() {
            _etaSeconds = 60; 
            _estimatedArrival = DateTime.now().add(const Duration(seconds: 60));
            _etaText = 'Less than 1 min';
          });
        }
        return;
      }
      
      final apiKey = MapsConfig.apiKey;
      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=$apiKey',
      );

      debugPrint('ETA Route URL: $url');
      final response = await http.get(url);
      debugPrint('ETA Route Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('ETA Route API Status: ${data['status']}');
        
        if (data['error_message'] != null) {
          debugPrint('❌ API Error Message: ${data['error_message']}');
        }
        
        if (data['status'] == 'OK' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final legs = route['legs'] as List;
          if (legs.isNotEmpty) {
            final leg = legs[0];
            final duration = leg['duration'] as Map<String, dynamic>;
            final durationInSeconds = duration['value'] as int;
            final durationText = duration['text'] as String;

            debugPrint('ETA Duration: $durationText ($durationInSeconds seconds)');

            final estimatedArrival = DateTime.now().add(Duration(seconds: durationInSeconds));

            if (mounted) {
              setState(() {
                _etaSeconds = durationInSeconds;
                _estimatedArrival = estimatedArrival;
                _etaText = durationText;
              });
              debugPrint('✅ ETA set: $_etaText, Arrival: $_estimatedArrival');
            }
          } else {
            debugPrint('⚠️ No legs in route');
            if (mounted) {
              setState(() {
                _etaText = 'Unable to calculate';
              });
            }
          }
        } else {
          debugPrint('⚠️ API returned status: ${data['status']}');
          
          if (data['status'] == 'REQUEST_DENIED') {
            final errorMessage = data['error_message'] ?? 'No error message provided';
            debugPrint('❌ API REQUEST_DENIED');
            debugPrint('❌ Error message: $errorMessage');
            debugPrint('❌ Possible causes:');
            debugPrint('   1. Directions API not enabled in Google Cloud Console');
            debugPrint('   2. API key restrictions blocking the request');
            debugPrint('   3. Billing not enabled for the Google Cloud project');
            debugPrint('   4. Invalid or expired API key');
            debugPrint('❌ Origin: ${origin.latitude}, ${origin.longitude}');
            debugPrint('❌ Destination: ${destination.latitude}, ${destination.longitude}');
            
            final distance = _calculateDistance(
              origin.latitude,
              origin.longitude,
              destination.latitude,
              destination.longitude,
            );
            
            debugPrint('❌ Calculated distance: ${distance.toStringAsFixed(3)} km');
            
            if (distance <= 1000 && distance > 0) {
              debugPrint('⚠️ Using fallback distance-based ETA (API unavailable)');
            _calculateFallbackETA(origin, destination);
            } else {
              debugPrint('⚠️ Distance invalid (${distance.toStringAsFixed(2)} km), skipping fallback ETA');
              if (mounted) {
                setState(() {
                  _etaText = 'Unable to calculate';
                });
              }
            }
          } else if (mounted) {
            setState(() {
              _etaText = 'Unable to calculate';
            });
          }
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          debugPrint('Response body status: ${data['status']}');
        }
        if (mounted) {
          setState(() {
            _etaText = 'Unable to calculate';
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching ETA route: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _etaText = 'Unable to calculate';
        });
      }
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

  
  void _calculateFallbackETA(LatLng origin, LatLng destination) {
    final distance = _calculateDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    
    if (distance > 1000) {
      debugPrint('⚠️ Distance too large for fallback ETA: ${distance.toStringAsFixed(2)} km');
      if (mounted) {
        setState(() {
          _etaText = 'Unable to calculate';
        });
      }
      return;
    }
    
    const double averageSpeedKmh = 30.0;
    final double hours = distance / averageSpeedKmh;
    final int minutes = (hours * 60).round();
    
    if (minutes < 1) {
      _etaText = 'Less than 1 min';
      _etaSeconds = 30;
    } else {
      _etaText = '$minutes min${minutes > 1 ? 's' : ''}';
      _etaSeconds = minutes * 60;
    }
    
    _estimatedArrival = DateTime.now().add(Duration(seconds: _etaSeconds ?? 0));
    
    if (mounted) {
      setState(() {
        
      });
    }
    
    debugPrint('✅ Fallback ETA calculated: $_etaText (distance: ${distance.toStringAsFixed(2)} km)');
  }

  String _formatETA() {
    if (_estimatedArrival == null) return _etaText;
    
    final now = DateTime.now();
    final difference = _estimatedArrival!.difference(now);
    
    
    final deliveryStatus = _delivery?['status']?.toString().toLowerCase() ?? '';
    final isDelivered = deliveryStatus == 'delivered' || deliveryStatus == 'completed';
    
    
    if (difference.isNegative) {
      return isDelivered ? 'Arrived' : 'Less than 1 min';
    }
    
    
    if (difference.inMinutes < 1) {
      return isDelivered ? 'Arrived' : 'Less than 1 min';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      final hours = difference.inHours;
      final minutes = difference.inMinutes.remainder(60);
      if (minutes == 0) {
        return '$hours hour${hours > 1 ? 's' : ''}';
      } else {
        return '$hours hour${hours > 1 ? 's' : ''} $minutes min${minutes > 1 ? 's' : ''}';
      }
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  void _updatePolylines() {
    if (!_isPaymentApproved) {
      setState(() {
        _polylines = {};
      });
      return;
    }
    
    final polylines = <Polyline>{};

    
    if (_pickupLocation != null && _dropoffLocation != null) {
      final routePoints = _routePoints ?? [_pickupLocation!, _dropoffLocation!];
      final hasRealRoute = routePoints.length > 2;
      
      if (hasRealRoute) {
        
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePoints,
            color: AppColors.primary,
            width: 4,
          ),
        );
      } else {
        
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePoints,
            color: AppColors.primary,
            width: 4,
            patterns: [PatternItem.dash(30), PatternItem.gap(10)],
          ),
        );
      }
    }

    
    if (_riderLocation != null && _dropoffLocation != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('rider_route'),
          points: [_riderLocation!, _dropoffLocation!],
          color: Colors.blue,
          width: 3,
          patterns: [PatternItem.dash(20), PatternItem.gap(5)],
        ),
      );
    }

    setState(() {
      _polylines = polylines;
    });
  }

  void _updateCamera() {
    if (!mounted || mapController == null || !_isPaymentApproved) return;

    try {
    final locations = <LatLng>[];
    if (_pickupLocation != null) locations.add(_pickupLocation!);
    if (_dropoffLocation != null) locations.add(_dropoffLocation!);
    if (_riderLocation != null) locations.add(_riderLocation!);
    
    if (_userLocation != null) {
      final deliveryLocations = <LatLng>[];
      if (_pickupLocation != null) deliveryLocations.add(_pickupLocation!);
      if (_dropoffLocation != null) deliveryLocations.add(_dropoffLocation!);
      
      if (deliveryLocations.isNotEmpty) {
        double maxDistance = 0;
        for (final loc in deliveryLocations) {
          final distance = _calculateDistance(
            _userLocation!.latitude,
            _userLocation!.longitude,
            loc.latitude,
            loc.longitude,
          );
          if (distance > maxDistance) maxDistance = distance;
        }
        
        if (maxDistance <= 10.0) {
          locations.add(_userLocation!);
        }
      }
    }

    if (locations.isEmpty) return;

    double minLat = locations.first.latitude;
    double maxLat = locations.first.latitude;
    double minLng = locations.first.longitude;
    double maxLng = locations.first.longitude;

    for (final loc in locations) {
      minLat = loc.latitude < minLat ? loc.latitude : minLat;
      maxLat = loc.latitude > maxLat ? loc.latitude : maxLat;
      minLng = loc.longitude < minLng ? loc.longitude : minLng;
      maxLng = loc.longitude > maxLng ? loc.longitude : maxLng;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final latDelta = (maxLat - minLat) * 1.5;
    final lngDelta = (maxLng - minLng) * 1.5;

    mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - latDelta, minLng - lngDelta),
          northeast: LatLng(maxLat + latDelta, maxLng + lngDelta),
        ),
        100.0, 
      ),
    );
    } catch (e) {
      debugPrint('Error updating camera: $e');
      
    }
  }

  String _getStatusText() {
    if (_delivery == null) return 'Loading...';
    final statusRaw = _delivery!['status'];
    final status = statusRaw?.toString().toLowerCase() ?? 'pending';
    final hasRider = _delivery!['rider_id'] != null;
    
    switch (status) {
      case 'pending':
        return 'Waiting for Merchant Confirmation';
      case 'accepted':
        if (hasRider) {
          final paymentRequested = _delivery!['payment_requested'] == true;
          if (_hasSubmittedPayment) {
            return 'Payment Pending Approval';
          } else if (paymentRequested) {
            return 'Payment Required';
          } else {
            return 'Waiting for Payment Request';
          }
        } else {
          return 'Order Accepted - Waiting for Rider';
        }
      case 'prepared':
        return 'Order Being Prepared';
      case 'ready':
        return 'Ready for Pickup';
      case 'assigned':
        return 'Rider Assigned';
      case 'picked_up':
      case 'picked up':
        return 'Order Picked Up';
      case 'in_transit':
      case 'in transit':
      case 'on_the_way':
      case 'on the way':
        return 'Rider is on the way';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  bool _canMarkAsCompleted() {
    if (_delivery == null) return false;
    final statusRaw = _delivery!['status'];
    final status = statusRaw?.toString().toLowerCase() ?? 'pending';
    return status == 'delivered';
  }

  bool _canSubmitPayment() {
    if (_delivery == null) return false;
    if (_hasSubmittedPayment) return false; 
    
    final paymentRequested = _delivery!['payment_requested'] == true;
    return paymentRequested;
  }

  Future<void> _showPaymentDialog() async {
    if (widget.orderId == null || _delivery == null) return;
    
    
    setState(() => _paymentRequestShown = true);

    final formKey = GlobalKey<FormState>();
    final referenceController = TextEditingController();
    final amountController = TextEditingController();
    final nameController = TextEditingController();
    File? paymentImage;
    bool isLoading = false;
    
    // Dispose controllers when dialog closes
    void disposeControllers() {
      try {
        referenceController.dispose();
      } catch (e) {
        // Controller already disposed, ignore
      }
      try {
        amountController.dispose();
      } catch (e) {
        // Controller already disposed, ignore
      }
      try {
        nameController.dispose();
      } catch (e) {
        // Controller already disposed, ignore
      }
    }
    
    double totalAmount = 0;
    try {
      final items = _delivery!['delivery_items'] as List<dynamic>? ?? [];
      debugPrint('Delivery items count: ${items.length}');
      
      for (final item in items) {
        final subtotal = item['subtotal'];
        debugPrint('Item subtotal: $subtotal (type: ${subtotal.runtimeType})');
        if (subtotal is num) {
          totalAmount += subtotal.toDouble();
        }
        // Add add-ons subtotal
        final addons = item['delivery_item_addons'] as List<dynamic>? ?? [];
        for (final addon in addons) {
          final addonSubtotal = addon['subtotal'];
          if (addonSubtotal is num) {
            totalAmount += addonSubtotal.toDouble();
          }
        }
      }
      debugPrint('Total from items: $totalAmount');
      
      final deliveryFee = _delivery!['delivery_fee'];
      if (deliveryFee is num) {
        totalAmount += deliveryFee.toDouble();
        debugPrint('Added delivery fee: ${deliveryFee.toDouble()}, Final total: $totalAmount');
      } else {
        debugPrint('Warning: delivery_fee is null or not a number');
      }
    } catch (e) {
      debugPrint('Error calculating total: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }

    
    amountController.text = totalAmount.toStringAsFixed(2);

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async {
          // Dispose controllers after dialog is closed
          WidgetsBinding.instance.addPostFrameCallback((_) {
            disposeControllers();
          });
          return true;
        },
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Submit Payment'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // Dispose controllers after dialog is closed
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    disposeControllers();
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SizedBox(
            width: MediaQuery.of(dialogContext).size.width * 0.9,
            child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                          
                  if (_delivery!['merchant_gcash_qr_url'] != null || _delivery!['merchant_gcash_number'] != null) ...[
                  const Text(
                      'Pay to Merchant',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                      if (_delivery!['merchant_gcash_qr_url'] != null)
                      GestureDetector(
                        onTap: () => _showFullScreenNetworkImage(
                          dialogContext,
                          _delivery!['merchant_gcash_qr_url'] as String,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Scan GCash QR Code',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Stack(
                                children: [
                                  Image.network(
                                    _delivery!['merchant_gcash_qr_url'] as String,
                                    width: 150,
                                    height: 150,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.qr_code, size: 100),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Material(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(15),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.fullscreen,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_delivery!['merchant_gcash_number'] != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.phone, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'GCash Number',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  Text(
                                    _delivery!['merchant_gcash_number'] as String,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),
                  ],
                  
                  const Text(
                    'Payment Receipt',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: isLoading ? null : () async {
                      try {
                        final pickedFile = await _imagePicker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (pickedFile != null) {
                          setDialogState(() {
                            paymentImage = File(pickedFile.path);
                          });
                        }
                      } catch (e) {
                        debugPrint('Error picking image: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error picking image: $e')),
                          );
                        }
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border, width: 2),
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.background,
                      ),
                      child: paymentImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 48,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to upload screenshot',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : GestureDetector(
                              onTap: () => _showFullScreenImage(context, paymentImage!),
                              child: Stack(
                                children: [
                                  ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                paymentImage!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Material(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(
                                          Icons.fullscreen,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      hintText: 'Enter transaction reference number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter reference number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: amountController,
                    readOnly: true,
                    enabled: false,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount (₱)',
                      hintText: '0.00',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.payments),
                      prefixText: '₱',
                      helperText: 'This amount matches your order total and cannot be changed',
                      filled: true,
                      fillColor: Colors.grey[100],
                      disabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Amount is required';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Invalid amount';
                      }
                      
                      final expectedAmount = totalAmount.toStringAsFixed(2);
                      final enteredAmount = amount.toStringAsFixed(2);
                      if (enteredAmount != expectedAmount) {
                        return 'Amount must exactly match order total (₱$expectedAmount)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name of Sender',
                      hintText: 'Enter your name as shown on GCash',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_circle),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter sender name';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () {
                Navigator.of(context).pop();
                // Dispose controllers after dialog is closed
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  disposeControllers();
                });
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (!formKey.currentState!.validate()) return;

                if (paymentImage == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please upload payment screenshot'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                setDialogState(() {
                  isLoading = true;
                });

                try {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) {
                    if (context.mounted) {
                      setDialogState(() => isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You must be logged in')),
                      );
                    }
                    return;
                  }

                  await _supabaseService.submitPayment(
                    deliveryId: widget.orderId!,
                    customerId: user.id,
                    paymentImage: paymentImage!,
                    referenceNumber: referenceController.text.trim(),
                    amount: double.parse(amountController.text.trim()),
                    senderName: nameController.text.trim(),
                  );

                  if (context.mounted) {
                    // Close dialog first, then dispose controllers after dialog is closed
                    Navigator.of(context).pop();
                    
                    // Dispose controllers after dialog is closed using post-frame callback
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      disposeControllers();
                    });
                    
                    setState(() {
                      _hasSubmittedPayment = true;
                      _paymentRequestShown = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment submitted successfully. Waiting for merchant approval...'),
                        backgroundColor: AppColors.success,
                        duration: Duration(seconds: 4),
                      ),
                    );
                    
                    await _checkPaymentStatus();
                    
                    _startPaymentStatusPolling();
                    
                    _loadDelivery();
                  }
                } catch (e, stackTrace) {
                  debugPrint('❌ Error submitting payment in UI:');
                  debugPrint('Error type: ${e.runtimeType}');
                  debugPrint('Error message: $e');
                  debugPrint('Stack trace: $stackTrace');
                  debugPrint('Delivery ID: ${widget.orderId}');
                  debugPrint('User ID: ${Supabase.instance.client.auth.currentUser?.id ?? 'null'}');
                  debugPrint('Payment image: ${paymentImage != null ? 'provided' : 'null'}');
                  debugPrint('Reference number: ${referenceController.text.trim()}');
                  debugPrint('Amount: ${amountController.text.trim()}');
                  debugPrint('Sender name: ${nameController.text.trim()}');
                  
                  if (context.mounted) {
                    setDialogState(() => isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to submit payment: ${e.toString()}'),
                        backgroundColor: AppColors.error,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Submit Payment'),
            ),
          ],
        ),
        ),
      ),
    );

    
    
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
    referenceController.dispose();
    amountController.dispose();
    nameController.dispose();
      } catch (e) {
        
        debugPrint('Error disposing controllers: $e');
      }
    });
  }

  void _showFullScreenImage(BuildContext context, File imageFile) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _FullScreenImageViewer(
        imageFile: imageFile,
        onDownload: () => _downloadImage(imageFile),
      ),
    );
  }

  void _showFullScreenNetworkImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _FullScreenNetworkImageViewer(
        imageUrl: imageUrl,
        onDownload: () => _downloadNetworkImage(imageUrl),
      ),
    );
  }

  Future<void> _downloadImage(File imageFile) async {
    try {
      
      
      Permission? permission;
      if (Platform.isAndroid) {
        
        try {
          permission = Permission.photos;
          var status = await permission.request();
          if (!status.isGranted) {
            
            permission = Permission.storage;
            status = await permission.request();
            if (!status.isGranted) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Permission is required to save images to gallery'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
              return;
            }
          }
        } catch (e) {
          
          permission = Permission.storage;
          final status = await permission.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Permission is required to save images to gallery'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
            return;
          }
        }
      } else if (Platform.isIOS) {
        permission = Permission.photos;
        final status = await permission.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permission is required to save images to gallery'),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
      }

      
      try {
        await Gal.putImage(
          imageFile.path,
          album: 'Lagona',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image saved to gallery successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop(); 
        }
      } catch (e) {
        debugPrint('Error saving image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save image'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadNetworkImage(String imageUrl) async {
    try {
      
      Permission? permission;
      if (Platform.isAndroid) {
        try {
          permission = Permission.photos;
          var status = await permission.request();
          if (!status.isGranted) {
            permission = Permission.storage;
            status = await permission.request();
            if (!status.isGranted) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Permission is required to save images to gallery'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
              return;
            }
          }
        } catch (e) {
          permission = Permission.storage;
          final status = await permission.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Permission is required to save images to gallery'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
            return;
          }
        }
      } else if (Platform.isIOS) {
        permission = Permission.photos;
        final status = await permission.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permission is required to save images to gallery'),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
      }

      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Downloading image...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        
        try {
          await Gal.putImage(
            filePath,
            album: 'Lagona',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('GCash QR code saved to gallery successfully'),
                backgroundColor: AppColors.success,
              ),
            );
            Navigator.of(context).pop(); 
          }
        } catch (e) {
          debugPrint('Error saving GCash QR code: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to save image'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to download image'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading network image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _markAsCompleted() async {
    if (widget.orderId == null || _delivery == null) return;

    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Completed'),
        content: const Text(
          'Are you sure you want to mark this delivery as completed? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be logged in to complete deliveries')),
          );
        }
        return;
      }

      await _supabaseService.completeDelivery(
        deliveryId: widget.orderId!,
        customerId: user.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery marked as completed'),
            backgroundColor: AppColors.success,
          ),
        );
        
        _loadDelivery();
      }
    } catch (e) {
      debugPrint('Error completing delivery: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete delivery: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Order'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Track Order'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    
    final initialCamera = _pickupLocation ?? 
                         _dropoffLocation ?? 
                         _riderLocation ?? 
                         _userLocation ?? 
                         const LatLng(14.5995, 120.9842);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusText(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          
          if (_isPaymentApproved)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialCamera,
                zoom: 13,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              compassEnabled: true,
              mapType: MapType.normal,
              onMapCreated: (controller) {
                mapController = controller;
                _updateCamera();
              },
            )
          else
            Container(
              color: Colors.grey[200],
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Map will be available after payment confirmation',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          
          
          if ((_delivery?['payment_requested'] == true && !_hasSubmittedPayment) ||
              (_hasSubmittedPayment && !_isPaymentApproved && _delivery?['status']?.toString().toLowerCase() != 'prepared'))
            Container(
              color: Colors.white.withOpacity(0.95),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.payment,
                        size: 64,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _hasSubmittedPayment 
                            ? 'Payment Pending Approval'
                            : 'Payment Required',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hasSubmittedPayment
                            ? 'Your payment has been submitted and is waiting for merchant approval. Tracking will be available once your payment is confirmed.'
                            : 'Please submit your payment to proceed. Tracking will be available once your payment is confirmed.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (_hasSubmittedPayment)
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[700]!),
                        ),
                    ],
                  ),
                ),
              ),
          ),
          
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Delivery Status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_delivery?['pickup_address'] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.store, size: 16, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'From: ${_delivery!['pickup_address']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_delivery?['dropoff_address'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'To: ${_delivery!['dropoff_address']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                            
                            if (_delivery?['delivery_notes'] != null && 
                                (_delivery!['delivery_notes'] as String).trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.note, size: 14, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Notes: ${_delivery!['delivery_notes']}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[700],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    
                    if (_delivery != null) ...[
                      Builder(
                        builder: (context) {
                          final statusRaw = _delivery!['status'];
                          final status = statusRaw?.toString().toLowerCase() ?? '';
                          final isPickedUpOrInTransit = status == 'picked_up' || 
                                                         status == 'picked up' || 
                                                         status == 'in_transit' || 
                                                         status == 'in transit';
                          final isDeliveredOrCompleted = status == 'delivered' || status == 'completed';
                          
                          if ((isPickedUpOrInTransit && _delivery!['pickup_image'] != null) ||
                              (isDeliveredOrCompleted && (_delivery!['pickup_image'] != null || _delivery!['dropoff_image'] != null)))
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isPickedUpOrInTransit 
                                        ? 'Pickup Verification'
                                        : 'Delivery Photos',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      
                                      if (_delivery!['pickup_image'] != null && 
                                          (isPickedUpOrInTransit || isDeliveredOrCompleted))
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _showFullScreenNetworkImage(
                                              context,
                                              _delivery!['pickup_image'] as String,
                                            ),
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.border),
                                              ),
                                              child: Column(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: const BorderRadius.vertical(
                                                      top: Radius.circular(7),
                                                    ),
                                                    child: Image.network(
                                                      _delivery!['pickup_image'] as String,
                                                      height: 100,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        height: 100,
                                                        color: Colors.grey[200],
                                                        child: const Icon(
                                                          Icons.image_not_supported,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        const Icon(
                                                          Icons.store,
                                                          size: 14,
                                                          color: Colors.green,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Text(
                                                          'Pickup',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(
                                                          Icons.fullscreen,
                                                          size: 12,
                                                          color: Colors.grey,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      
                                      if (_delivery!['dropoff_image'] != null && isDeliveredOrCompleted)
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _showFullScreenNetworkImage(
                                              context,
                                              _delivery!['dropoff_image'] as String,
                                            ),
                                            child: Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppColors.border),
                                              ),
                                              child: Column(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: const BorderRadius.vertical(
                                                      top: Radius.circular(7),
                                                    ),
                                                    child: Image.network(
                                                      _delivery!['dropoff_image'] as String,
                                                      height: 100,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        height: 100,
                                                        color: Colors.grey[200],
                                                        child: const Icon(
                                                          Icons.image_not_supported,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        const Icon(
                                                          Icons.location_on,
                                                          size: 14,
                                                          color: Colors.red,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Text(
                                                          'Dropoff',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(
                                                          Icons.fullscreen,
                                                          size: 12,
                                                          color: Colors.grey,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                    
                    if (_delivery != null && 
                        (_delivery!['status']?.toString().toLowerCase() ?? '') == 'pending')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_empty, size: 20, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your order is waiting for merchant confirmation. The merchant will check availability based on stock.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    Builder(
                      builder: (context) {
                        final statusRaw = _delivery?['status'];
                        final currentStatus = statusRaw?.toString().toLowerCase() ?? '';
                        final isPickedUp = currentStatus == 'picked_up' || currentStatus == 'picked up';
                        final isInTransit = currentStatus == 'in_transit' || 
                                           currentStatus == 'in transit' || 
                                           currentStatus == 'on_the_way' || 
                                           currentStatus == 'on the way';
                        
                        if (_delivery != null && isPickedUp && _delivery!['pickup_image'] != null)
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 20, color: Colors.green[700]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Order has been picked up by the rider. The rider is now on the way to your location.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[900],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        return const SizedBox.shrink();
                      },
                    ),
                    
                    if (_delivery != null && 
                        _delivery!['rider_id'] != null &&
                        _delivery!['payment_requested'] != true &&
                        !_hasSubmittedPayment)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_empty, size: 20, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Rider assigned! Waiting for merchant to request payment.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    if (_delivery != null && 
                        _delivery!['payment_requested'] == true &&
                        !_hasSubmittedPayment)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.payment, size: 20, color: Colors.green[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Payment requested! Please submit your payment to proceed.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    
                    if (_delivery != null && 
                        _hasSubmittedPayment &&
                        !_isPaymentApproved &&
                        _delivery!['rider_id'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_empty, size: 20, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isPaymentApproved 
                                    ? 'Payment approved! Tracking your order...'
                                    : 'Payment submitted! Waiting for merchant approval.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    if (_riderLocation != null && _isPaymentApproved)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.motorcycle, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Rider is on the way',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _estimatedArrival != null
                                              ? 'ETA: ${_formatETA()}'
                                              : 'ETA: $_etaText',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _etaText == 'Unable to calculate'
                                                ? Colors.red
                                                : AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    if (_canSubmitPayment())
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showPaymentDialog,
                            icon: const Icon(Icons.payment, size: 20),
                            label: const Text('Submit Payment'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    if (_canMarkAsCompleted())
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _markAsCompleted,
                            icon: const Icon(Icons.check_circle, size: 20),
                            label: const Text('Mark as Completed'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
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


class _FullScreenImageViewer extends StatelessWidget {
  final File imageFile;
  final VoidCallback onDownload;

  const _FullScreenImageViewer({
    required this.imageFile,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                imageFile,
                fit: BoxFit.contain,
              ),
            ),
          ),
          
          Positioned(
            top: 40,
            left: 20,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(25),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          
          Positioned(
            top: 40,
            right: 20,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                onTap: onDownload,
                borderRadius: BorderRadius.circular(25),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _FullScreenNetworkImageViewer extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onDownload;

  const _FullScreenNetworkImageViewer({
    required this.imageUrl,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.white, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          
          Positioned(
            top: 40,
            left: 20,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(25),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          
          Positioned(
            top: 40,
            right: 20,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                onTap: onDownload,
                borderRadius: BorderRadius.circular(25),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}