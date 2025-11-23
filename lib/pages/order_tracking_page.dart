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
  bool _isLoading = true;
  String? _errorMessage;
  List<LatLng>? _routePoints;
  final ImagePicker _imagePicker = ImagePicker();
  
  // ETA related
  int? _etaSeconds; // Estimated time in seconds
  DateTime? _estimatedArrival;
  String _etaText = 'Calculating...';
  Timer? _etaTimer;
  
  // Payment tracking
  bool _paymentRequestShown = false;
  bool _hasSubmittedPayment = false;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) {
      _loadDelivery();
      _getUserLocation();
      // Check payment status on initial load
      _checkPaymentStatus();
      // Start polling - will adjust interval based on status
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
    // Poll more frequently when:
    // - Waiting for merchant confirmation (pending)
    // - Order accepted but rider not assigned yet
    // - Rider assigned but payment not requested yet
    // - Payment requested but not submitted
    // Less frequently when payment submitted or rider tracking (every 10 seconds)
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
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _etaTimer?.cancel();
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

      // Extract locations
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

      // Get rider location if assigned
      if (delivery['rider_id'] != null && delivery['riders'] != null) {
        final riderData = delivery['riders'] as Map<String, dynamic>;
        final riderLat = riderData['latitude'] as double?;
        final riderLng = riderData['longitude'] as double?;
        if (riderLat != null && riderLng != null) {
          rider = LatLng(riderLat, riderLng);
        }
      }

      // Check if merchant has requested payment
      final deliveryStatus = delivery['status']?.toString().toLowerCase() ?? '';
      final previousStatus = _delivery?['status']?.toString().toLowerCase() ?? '';
      final hasRider = delivery['rider_id'] != null;
      final paymentRequested = delivery['payment_requested'] == true;
      final previousPaymentRequested = _delivery?['payment_requested'] == true;
      
      // Check if payment has been submitted by checking payments table
      if (paymentRequested && !_hasSubmittedPayment && !_paymentRequestShown) {
        await _checkPaymentStatus();
      }
      
      // Show payment dialog when merchant requests payment and payment hasn't been submitted
      if (paymentRequested && 
          !previousPaymentRequested && 
          !_hasSubmittedPayment && 
          !_paymentRequestShown && 
          mounted) {
        // Merchant just requested payment
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
        
        // Adjust polling interval based on status
        if (previousStatus != deliveryStatus) {
          _startPolling();
        }
        _updateMarkers();
        
        // Fetch route from pickup to dropoff using Directions API (only once)
        if (pickup != null && dropoff != null && _routePoints == null) {
          await _fetchRoute(pickup, dropoff);
        } else {
          _updatePolylines();
        }
        
        // Fetch ETA from rider to user's current location if rider is assigned
        // If user location is not available yet, fallback to dropoff location
        final etaDestination = _userLocation ?? dropoff;
        
        if (rider != null && etaDestination != null) {
          // Fetch ETA using the same route API if rider location changed or ETA hasn't been calculated yet
          if (riderLocationChanged || _estimatedArrival == null || _userLocation != null) {
            await _fetchRouteForETA(rider, etaDestination);
          }
          // Start timer to update ETA countdown every 30 seconds
          _etaTimer?.cancel();
          _etaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
            if (mounted && _estimatedArrival != null) {
              setState(() {
                // Trigger rebuild to update ETA display
              });
            }
            // Re-fetch ETA periodically if rider location might have changed
            // Use user location if available, otherwise dropoff
            if (mounted && rider != null) {
              final destination = _userLocation ?? dropoff;
              if (destination != null) {
                _fetchRouteForETA(rider, destination);
              }
            }
          });
        } else {
          // Cancel timer if no rider
          _etaTimer?.cancel();
          if (mounted) {
            setState(() {
              _etaText = 'Calculating...';
              _estimatedArrival = null;
            });
          }
        }
        
        _updateCamera();
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
      debugPrint('=== Checking payment status ===');
      
      // Check if payment has been submitted for this delivery
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      final payments = await Supabase.instance.client
          .from('payments')
          .select('id, status')
          .eq('delivery_id', widget.orderId!)
          .eq('customer_id', user.id);
      
      if (payments.isNotEmpty) {
        setState(() {
          _hasSubmittedPayment = true;
          _paymentRequestShown = true;
        });
        debugPrint('✅ Payment already submitted');
      }
    } catch (e) {
      debugPrint('Error checking payment status: $e');
    }
  }

  Future<void> _getUserLocation() async {
    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
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
    final markers = <Marker>{};

    // Pickup marker (merchant)
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

    // Dropoff marker (customer)
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

    // Rider marker (if assigned)
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

    // User location marker (current location)
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
          
          // Extract duration from the route for ETA
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
      // Fall back to straight line if API fails
      setState(() {
        _routePoints = null;
      });
      _updatePolylines();
    }
  }

  // Fetch route specifically for ETA calculation (rider to dropoff)
  Future<void> _fetchRouteForETA(LatLng origin, LatLng destination) async {
    try {
      debugPrint('=== Fetching ETA Route ===');
      debugPrint('Origin: ${origin.latitude}, ${origin.longitude}');
      debugPrint('Destination: ${destination.latitude}, ${destination.longitude}');
      
      // Check distance - only show "Arrived" if very close AND delivery is actually delivered
      final distance = _calculateDistance(
        origin.latitude, 
        origin.longitude, 
        destination.latitude, 
        destination.longitude
      );
      
      debugPrint('Distance between rider and destination: ${distance.toStringAsFixed(3)} km');
      
      // Only show "Arrived" if delivery status is delivered/completed
      // For in-transit orders, always calculate ETA even if close
      final deliveryStatus = _delivery?['status']?.toString().toLowerCase() ?? '';
      final isDelivered = deliveryStatus == 'delivered' || deliveryStatus == 'completed';
      
      // If very close (less than 100m) and status is delivered, show arrived
      if (distance < 0.1 && isDelivered) { // Less than 100 meters
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
      
      // If very close but still in transit, show "Less than 1 min" instead of "Arrived"
      if (distance < 0.1) {
        debugPrint('⚠️ Rider is very close (<100m) but delivery is still in transit');
        if (mounted) {
          setState(() {
            _etaSeconds = 60; // 1 minute
            _estimatedArrival = DateTime.now().add(const Duration(seconds: 60));
            _etaText = 'Less than 1 min';
          });
        }
        return;
      }
      
      final apiKey = MapsConfig.apiKey;
      // Use the same URL format as _fetchRoute which works
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
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
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
          // If API is denied, calculate fallback ETA based on distance
          if (data['status'] == 'REQUEST_DENIED') {
            debugPrint('⚠️ API denied, using fallback distance-based ETA');
            _calculateFallbackETA(origin, destination);
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

  // Fallback ETA calculation based on distance (when API is not available)
  void _calculateFallbackETA(LatLng origin, LatLng destination) {
    final distance = _calculateDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    
    // Assume average speed of 30 km/h for city delivery
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
        // State already updated above
      });
    }
    
    debugPrint('✅ Fallback ETA calculated: $_etaText (distance: ${distance.toStringAsFixed(2)} km)');
  }

  String _formatETA() {
    if (_estimatedArrival == null) return _etaText;
    
    final now = DateTime.now();
    final difference = _estimatedArrival!.difference(now);
    
    // Only show "Arrived" if delivery status is actually delivered/completed
    final deliveryStatus = _delivery?['status']?.toString().toLowerCase() ?? '';
    final isDelivered = deliveryStatus == 'delivered' || deliveryStatus == 'completed';
    
    // If negative (past ETA), check status
    if (difference.isNegative) {
      return isDelivered ? 'Arrived' : 'Less than 1 min';
    }
    
    // If less than 1 minute, show "Less than 1 min" instead of "Arrived"
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
    final polylines = <Polyline>{};

    // Route from pickup to dropoff (use Directions API route if available)
    if (_pickupLocation != null && _dropoffLocation != null) {
      final routePoints = _routePoints ?? [_pickupLocation!, _dropoffLocation!];
      final hasRealRoute = routePoints.length > 2;
      
      if (hasRealRoute) {
        // Real route from Directions API - solid line
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePoints,
            color: AppColors.primary,
            width: 4,
          ),
        );
      } else {
        // Straight line fallback - dashed pattern
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

    // Polyline from rider to dropoff (if rider is assigned)
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
    if (!mounted || mapController == null) return;

    try {
      final locations = <LatLng>[];
      if (_pickupLocation != null) locations.add(_pickupLocation!);
      if (_dropoffLocation != null) locations.add(_dropoffLocation!);
      if (_riderLocation != null) locations.add(_riderLocation!);
      if (_userLocation != null) locations.add(_userLocation!);

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
          100.0, // padding in pixels
        ),
      );
    } catch (e) {
      debugPrint('Error updating camera: $e');
      // Controller might be disposed, ignore the error
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
        return 'Picked Up';
      case 'in_transit':
      case 'in transit':
        return 'On the Way';
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
    if (_hasSubmittedPayment) return false; // Already submitted
    // Can submit payment only when merchant has requested payment
    final paymentRequested = _delivery!['payment_requested'] == true;
    return paymentRequested;
  }

  Future<void> _showPaymentDialog() async {
    if (widget.orderId == null || _delivery == null) return;
    
    // Mark that payment dialog has been shown
    setState(() => _paymentRequestShown = true);

    final formKey = GlobalKey<FormState>();
    final referenceController = TextEditingController();
    final amountController = TextEditingController();
    final nameController = TextEditingController();
    File? paymentImage;
    bool isLoading = false;

    // Calculate total amount from delivery items
    // First check if there's a direct total_amount field
    double totalAmount = 0;
    try {
      // Check for direct total_amount field first
      if (_delivery!['total_amount'] != null) {
        final totalAmountValue = _delivery!['total_amount'];
        if (totalAmountValue is num) {
          totalAmount = totalAmountValue.toDouble();
        }
      } else {
        // Calculate from delivery items if total_amount is not available
        final items = _delivery!['delivery_items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final subtotal = item['subtotal'];
          if (subtotal is num) {
            totalAmount += subtotal.toDouble();
          }
        }
        final deliveryFee = _delivery!['delivery_fee'];
        if (deliveryFee is num) {
          totalAmount += deliveryFee.toDouble();
        }
      }
    } catch (e) {
      debugPrint('Error calculating total: $e');
    }

    // Pre-fill amount with total (read-only)
    amountController.text = totalAmount.toStringAsFixed(2);

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Submit Payment'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
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
                          // Merchant GCash Info
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
                  // Payment Image Upload
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
                  // Reference Number
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
                  // Amount (read-only, matches order total)
                  TextFormField(
                    controller: amountController,
                    readOnly: true,
                    style: TextStyle(
                      color: Colors.grey[700],
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount (₱)',
                      hintText: '0.00',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.attach_money),
                      prefixText: '₱',
                      helperText: 'This amount matches your order total',
                      filled: true,
                      fillColor: Colors.grey[100],
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
                      // Validate that the entered amount matches the calculated total
                      final expectedAmount = totalAmount.toStringAsFixed(2);
                      if (value.trim() != expectedAmount) {
                        return 'Amount must match order total (₱$expectedAmount)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Sender Name
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
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
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
                    setState(() {
                      _hasSubmittedPayment = true;
                      _paymentRequestShown = true;
                    });
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment submitted successfully. Waiting for rider assignment...'),
                        backgroundColor: AppColors.success,
                        duration: Duration(seconds: 4),
                      ),
                    );
                    // Reload delivery to update status
                    _loadDelivery();
                  }
                } catch (e) {
                  debugPrint('Error submitting payment: $e');
                  if (context.mounted) {
                    setDialogState(() => isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to submit payment: ${e.toString()}'),
                        backgroundColor: AppColors.error,
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
    );

    referenceController.dispose();
    amountController.dispose();
    nameController.dispose();
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
      // Request appropriate permission based on platform
      // Try photos first (Android 13+ and iOS), fallback to storage for older Android
      Permission? permission;
      if (Platform.isAndroid) {
        // Try photos permission first (Android 13+)
        try {
          permission = Permission.photos;
          var status = await permission.request();
          if (!status.isGranted) {
            // Fallback to storage for older Android versions
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
          // If photos permission is not available, use storage
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

      // Save image to gallery
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
          Navigator.of(context).pop(); // Close full-screen viewer
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
      // Request appropriate permission based on platform
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

      // Show loading indicator
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

      // Download the image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        // Get temporary directory
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/gcash_qr_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Save to gallery
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
            Navigator.of(context).pop(); // Close full-screen viewer
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

    // Show confirmation dialog
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
        // Reload delivery to update status
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

    // Determine initial camera position
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
          ),
          // Status card overlay
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
                            // Show delivery notes if available
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
                    // Show status message for pending orders
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
                    // Show status message when rider is assigned but payment not requested yet
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
                    // Show status message when payment is requested
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
                    // Show status message after payment submitted (waiting for merchant approval)
                    if (_delivery != null && 
                        _hasSubmittedPayment &&
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
                                  'Payment submitted! Waiting for merchant approval.',
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
                    if (_riderLocation != null)
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
                                  // Always show ETA when rider is assigned
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
                    // Payment button (show for accepted orders before payment)
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
                    // Mark as completed button (only show when delivered)
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

// Full-screen image viewer widget
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
          // Full-screen image
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
          // Close button
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
          // Download button
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

// Full-screen network image viewer widget
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
          // Full-screen image
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
          // Close button
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
          // Download button
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


