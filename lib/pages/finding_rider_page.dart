import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/rider_search_service.dart';
import '../services/supabase_service.dart';
import 'order_tracking_page.dart';

class FindingRiderPage extends StatefulWidget {
	static const String routeName = '/finding-rider';
	final String orderId;
	const FindingRiderPage({super.key, required this.orderId});

	@override
	State<FindingRiderPage> createState() => _FindingRiderPageState();
}

class _FindingRiderPageState extends State<FindingRiderPage> with SingleTickerProviderStateMixin {
	static const Duration pollInterval = Duration(seconds: 5);
	static const Duration timeout = Duration(minutes: 5);
	static const double searchRadiusKm = 5.0;

	final RiderSearchService _service = RiderSearchService();
	final SupabaseService _supabaseService = SupabaseService();
	Timer? _pollTimer;
	Timer? _timeoutTimer;
	DateTime _startedAt = DateTime.now();
	bool _isSearching = true;
	String _statusText = 'Finding a rider nearby...';
	LatLng? _userLatLng;
	AnimationController? _pulseController;

	@override
	void initState() {
		super.initState();
		_pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
		_initAndStart();
	}

	Future<void> _initAndStart() async {
		_startedAt = DateTime.now();
		final pos = await _getCurrentPosition();
		if (!mounted) return;
		setState(() => _userLatLng = LatLng(pos.latitude, pos.longitude));
		_startPolling();
		_startTimeout();
	}

	Future<Position> _getCurrentPosition() async {
		
		bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
		if (!serviceEnabled) {
			throw Exception('Location services are disabled. Please enable location services.');
		}
		
		
		LocationPermission permission = await Geolocator.checkPermission();
		if (permission == LocationPermission.denied) {
			permission = await Geolocator.requestPermission();
			if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
				throw Exception('Location permission is required to find nearby riders.');
			}
		}
		if (permission == LocationPermission.deniedForever) {
			throw Exception('Location permission was permanently denied. Please enable it in settings.');
		}
		
		return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
	}

	void _startPolling() {
		_pollTimer?.cancel();
		_pollTimer = Timer.periodic(pollInterval, (_) => _poll());
	}

	void _startTimeout() {
		_timeoutTimer?.cancel();
		_timeoutTimer = Timer(timeout, _exhausted);
	}

	Future<void> _poll() async {
		if (!_isSearching || _userLatLng == null) return;
		setState(() => _statusText = 'Searching riders within ${searchRadiusKm.toStringAsFixed(0)} km...');
		final match = await _service.findNearbyRider(_userLatLng!, radiusKm: searchRadiusKm);
		if (!mounted) return;
		if (match != null) {
			_stopAll();
			setState(() {
				_isSearching = false;
				_statusText = 'Rider found! Assigning to delivery...';
			});
			
			
			try {
				await _supabaseService.assignRiderToDelivery(
					deliveryId: widget.orderId,
					riderId: match.riderId,
				);
				
				if (!mounted) return;
				setState(() {
					_statusText = 'Rider assigned! Starting tracking...';
				});
				
				
				await Future<void>.delayed(const Duration(milliseconds: 400));
				if (!mounted) return;
				Navigator.of(context).pushReplacementNamed(
					OrderTrackingPage.routeName,
					arguments: widget.orderId,
				);
			} catch (e) {
				if (!mounted) return;
				setState(() {
					_isSearching = false;
					_statusText = 'Error assigning rider. Please try again.';
				});
			}
		} else {
			final elapsed = DateTime.now().difference(_startedAt);
			setState(() => _statusText = 'Still searching... (${elapsed.inSeconds}s elapsed)');
		}
	}

	void _exhausted() {
		_stopAll();
		if (!mounted) return;
		setState(() {
			_isSearching = false;
			_statusText = 'No rider available within 5 km. Please try again.';
		});
	}

	void _stopAll() {
		_pollTimer?.cancel();
		_timeoutTimer?.cancel();
		_pulseController?.stop();
	}

	@override
	void dispose() {
		_stopAll();
		_pulseController?.dispose();
		super.dispose();
	}

	void _retry() {
		setState(() {
			_isSearching = true;
			_statusText = 'Finding a rider nearby...';
			_startedAt = DateTime.now();
		});
		_pulseController?.repeat(reverse: true);
		_startPolling();
		_startTimeout();
	}

	@override
	Widget build(BuildContext context) {
		final elapsed = DateTime.now().difference(_startedAt);
		final remaining = timeout - elapsed;
		return Scaffold(
			appBar: AppBar(title: const Text('Finding Rider')),
			body: Center(
				child: Padding(
					padding: const EdgeInsets.all(24),
					child: Column(
						mainAxisAlignment: MainAxisAlignment.center,
						children: [
							ScaleTransition(
								scale: Tween<double>(begin: 0.95, end: 1.05).animate(_pulseController!),
								child: const CircleAvatar(
									radius: 36,
									child: Icon(Icons.motorcycle, size: 36),
								),
							),
							const SizedBox(height: 16),
							Text(_statusText, textAlign: TextAlign.center),
							const SizedBox(height: 8),
							if (_isSearching)
								Text('Timeout in ${remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
										'${(remaining.inSeconds.remainder(60)).toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.grey)),
							const SizedBox(height: 24),
							if (_isSearching) const LinearProgressIndicator(minHeight: 6),
							if (!_isSearching) ...[
								const SizedBox(height: 12),
								Row(
									mainAxisAlignment: MainAxisAlignment.center,
									children: [
										OutlinedButton(
											onPressed: _retry,
											child: const Text('Retry'),
										),
										const SizedBox(width: 12),
										TextButton(
											onPressed: () => Navigator.of(context).pop(),
											child: const Text('Cancel'),
										),
									],
								)
							]
						],
					),
				),
			),
		);
	}
}


