import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import '../models/padala.dart';

class PadalaTrackingPage extends StatefulWidget {
  static const String routeName = '/padala-tracking';
  final String? padalaId;
  
  const PadalaTrackingPage({super.key, this.padalaId});

  @override
  State<PadalaTrackingPage> createState() => _PadalaTrackingPageState();
}

class _PadalaTrackingPageState extends State<PadalaTrackingPage> {
  GoogleMapController? _mapController;
  final SupabaseService _supabaseService = SupabaseService();
  
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  
  PadalaDelivery? _padala;
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  LatLng? _riderLocation;
  
  Timer? _updateTimer;
  bool _isLoading = true;
  String? _errorMessage;
  String? _padalaId;
  
  @override
  void initState() {
    super.initState();
    _padalaId = widget.padalaId;
    if (_padalaId != null) {
      _loadPadala();
      _startPolling();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No Padala ID provided';
      });
    }
  }
  
  void _startPolling() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _loadPadala();
    });
  }
  
  Future<void> _loadPadala() async {
    if (_padalaId == null) return;
    try {
      final padalaData = await _supabaseService.getPadalaById(_padalaId!);
      
      if (padalaData == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Padala delivery not found';
        });
        return;
      }
      
      final padala = PadalaDelivery.fromMap(padalaData);
      
      setState(() {
        _padala = padala;
        _pickupLocation = LatLng(padala.pickupLatitude, padala.pickupLongitude);
        _dropoffLocation = LatLng(padala.dropoffLatitude, padala.dropoffLongitude);
        
        // Get rider location if available
        if (padalaData['riders'] != null) {
          final rider = padalaData['riders'] as Map<String, dynamic>;
          final riderLat = rider['latitude'] as double?;
          final riderLng = rider['longitude'] as double?;
          if (riderLat != null && riderLng != null) {
            _riderLocation = LatLng(riderLat, riderLng);
          }
        }
        
        _isLoading = false;
      });
      
      _updateMap();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading Padala: $e';
        });
      }
    }
  }
  
  void _updateMap() {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    
    final markers = <Marker>{};
    
    // Pickup marker
    markers.add(
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup Location',
          snippet: _padala?.pickupAddress ?? '',
        ),
      ),
    );
    
    // Dropoff marker
    markers.add(
      Marker(
        markerId: const MarkerId('dropoff'),
        position: _dropoffLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Dropoff Location',
          snippet: _padala?.dropoffAddress ?? '',
        ),
      ),
    );
    
    // Rider marker (if available)
    if (_riderLocation != null && _padala?.canTrack == true) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: _riderLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(
            title: 'Rider Location',
            snippet: 'Your package is here',
          ),
        ),
      );
    }
    
    setState(() {
      _markers = markers;
    });
    
    // Update camera to show all markers
    if (_mapController != null && _pickupLocation != null && _dropoffLocation != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          math.min(_pickupLocation!.latitude, _dropoffLocation!.latitude) - 0.01,
          math.min(_pickupLocation!.longitude, _dropoffLocation!.longitude) - 0.01,
        ),
        northeast: LatLng(
          math.max(_pickupLocation!.latitude, _dropoffLocation!.latitude) + 0.01,
          math.max(_pickupLocation!.longitude, _dropoffLocation!.longitude) + 0.01,
        ),
      );
      
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }
  
  @override
  void dispose() {
    _updateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
  
  String _getStatusText() {
    if (_padala == null) return 'Loading...';
    
    switch (_padala!.status) {
      case PadalaStatus.pending:
        return 'Waiting for rider to accept...';
      case PadalaStatus.accepted:
        return 'Rider is on the way to pickup location';
      case PadalaStatus.pickedUp:
        return 'Package picked up, rider is heading to dropoff';
      case PadalaStatus.inTransit:
        return 'Package is on the way to recipient';
      case PadalaStatus.dropoff:
        return 'Package has been dropped off';
      case PadalaStatus.completed:
        return 'Delivery completed successfully!';
      case PadalaStatus.cancelled:
        return 'Delivery cancelled';
    }
  }
  
  Widget _buildStatusCard() {
    if (_padala == null) return const SizedBox.shrink();
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _padala!.status == PadalaStatus.dropoff ||
                  _padala!.status == PadalaStatus.completed
                      ? Icons.check_circle
                      : Icons.local_shipping,
                  color: _padala!.status == PadalaStatus.dropoff ||
                          _padala!.status == PadalaStatus.completed
                      ? AppColors.success
                      : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _padala!.statusDisplay,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('Sender', _padala!.senderName),
            _buildInfoRow('Recipient', _padala!.recipientName),
            if (_padala!.packageDescription != null)
              _buildInfoRow('Package', _padala!.packageDescription!),
            
            // Cancel button (only show if delivery can be cancelled)
            if (_padala!.status == PadalaStatus.pending ||
                _padala!.status == PadalaStatus.accepted) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelDelivery(),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel Delivery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Future<void> _cancelDelivery() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Delivery'),
        content: const Text('Are you sure you want to cancel this Padala delivery?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null && _padalaId != null) {
          await _supabaseService.cancelDelivery(
            deliveryId: _padalaId!,
            customerId: user.id,
          );

          if (mounted) {
            // Return true to indicate delivery was cancelled
            Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Padala delivery cancelled successfully'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error cancelling delivery: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDeliveryProofCard() {
    if (_padala == null || !_padala!.isDelivered || _padala!.dropoffPhotoUrl == null) {
      return const SizedBox.shrink();
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Proof',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _padala!.dropoffPhotoUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: AppColors.border,
                    child: const Icon(Icons.error),
                  );
                },
              ),
            ),
            if (_padala!.deliveredAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Delivered at: ${_padala!.deliveredAt!.toString().substring(0, 19)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // Get padalaId from route arguments if not set
    if (_padalaId == null) {
      final routePadalaId = ModalRoute.of(context)?.settings.arguments as String?;
      if (routePadalaId != null && _padalaId != routePadalaId) {
        _padalaId = routePadalaId;
        if (mounted) {
          _loadPadala();
          _startPolling();
        }
      }
    }
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tracking Padala Delivery')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tracking Padala Delivery')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_errorMessage!),
            ],
          ),
        ),
      );
    }
    
    if (_pickupLocation == null || _dropoffLocation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tracking Padala Delivery')),
        body: const Center(child: Text('Invalid delivery locations')),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Padala Delivery'),
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pickupLocation!,
              zoom: 13,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              _updateMap();
            },
          ),
          
          // Status card at bottom
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.25,
            maxChildSize: 0.75,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    _buildStatusCard(),
                    _buildDeliveryProofCard(),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

