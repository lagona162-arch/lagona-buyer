import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';
import 'order_tracking_page.dart';
import 'padala_tracking_page.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';

class OrderHistoryPage extends StatefulWidget {
  static const String routeName = '/order-history';
  final int? initialTabIndex;
  const OrderHistoryPage({super.key, this.initialTabIndex});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage>
    with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  late TabController _tabController;
  
  List<Map<String, dynamic>> _allDeliveries = [];
  List<Map<String, dynamic>> _pendingDeliveries = [];
  List<Map<String, dynamic>> _completedDeliveries = [];
  List<Map<String, dynamic>> _cancelledDeliveries = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex ?? 0;
    _tabController = TabController(length: 4, vsync: this, initialIndex: initialIndex.clamp(0, 3));
    _loadDeliveries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _markAsCompleted(Map<String, dynamic> delivery) async {
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
        deliveryId: delivery['id'] as String,
        customerId: user.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery marked as completed'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadDeliveries();
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

  Future<void> _loadDeliveries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not logged in';
        });
        return;
      }

      final deliveries = await _supabaseService.getCustomerDeliveries(
        customerId: user.id,
      );

      debugPrint('=== Order History Debug ===');
      debugPrint('Total deliveries fetched: ${deliveries.length}');
      
      for (var i = 0; i < deliveries.length; i++) {
        final delivery = deliveries[i];
        final status = delivery['status'];
        final statusStr = status?.toString().toLowerCase().trim() ?? 'null';
        debugPrint('Delivery $i - ID: ${delivery['id']}, Status: $status (normalized: $statusStr)');
      }

      final pending = deliveries.where((d) {
        final statusRaw = d['status'];
        final status = statusRaw?.toString().toLowerCase().trim() ?? 'pending';
        final isCompleted = status == 'delivered' || status == 'completed';
        final isCancelled = status == 'cancelled';
        final isPending = !isCompleted && !isCancelled;
        debugPrint('  → Delivery ${d['id']}: status="$status", isCompleted=$isCompleted, isCancelled=$isCancelled, isPending=$isPending');
        return isPending;
      }).toList();

      final completed = deliveries.where((d) {
        final statusRaw = d['status'];
        final status = statusRaw?.toString().toLowerCase() ?? '';
        return status == 'delivered' || status == 'completed';
      }).toList();

      final cancelled = deliveries.where((d) {
        final statusRaw = d['status'];
        final status = statusRaw?.toString().toLowerCase() ?? '';
        return status == 'cancelled';
      }).toList();

      debugPrint('=== Filter Results ===');
      debugPrint('Pending count: ${pending.length}');
      debugPrint('Completed count: ${completed.length}');
      debugPrint('Cancelled count: ${cancelled.length}');
      if (pending.isNotEmpty) {
        debugPrint('Pending order IDs: ${pending.map((d) => d['id']).join(', ')}');
      }

      if (mounted) {
        setState(() {
          _allDeliveries = deliveries;
          _pendingDeliveries = pending;
          _completedDeliveries = completed;
          _cancelledDeliveries = cancelled;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading deliveries: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load orders: $e';
        });
      }
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    final normalizedStatus = status.toLowerCase().trim();
    switch (normalizedStatus) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'assigned':
        return Colors.blue.shade700;
      case 'picked_up':
      case 'picked up':
      case 'in_transit':
      case 'in transit':
      case 'on_the_way':
      case 'on the way':
        return Colors.purple;
      case 'delivered':
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    if (status == null) return 'Unknown';
    final normalizedStatus = status.toLowerCase().trim();
    switch (normalizedStatus) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'assigned':
        return 'Rider Assigned';
      case 'picked_up':
      case 'picked up':
        return 'Picked Up';
      case 'in_transit':
      case 'in transit':
      case 'on_the_way':
      case 'on the way':
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

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(date);
    } catch (e) {
      return dateString;
    }
  }

  double _calculateTotal(Map<String, dynamic> delivery) {
    try {
      final items = delivery['delivery_items'] as List<dynamic>? ?? [];
      double total = 0;
      for (final item in items) {
        final subtotal = item['subtotal'];
        if (subtotal is num) {
          total += subtotal.toDouble();
        }
        // Add add-ons subtotal
        final addons = item['delivery_item_addons'] as List<dynamic>? ?? [];
        for (final addon in addons) {
          final addonSubtotal = addon['subtotal'];
          if (addonSubtotal is num) {
            total += addonSubtotal.toDouble();
          }
        }
      }
      final deliveryFee = delivery['delivery_fee'];
      if (deliveryFee is num) {
        total += deliveryFee.toDouble();
      }
      return total;
    } catch (e) {
      debugPrint('Error calculating total: $e');
      return 0;
    }
  }

  Widget _buildDeliveryCard(Map<String, dynamic> delivery) {
    final type = delivery['type']?.toString().toLowerCase() ?? 'food';
    final isPadala = type == 'parcel';
    
    // Get merchant info for food orders
    final merchant = delivery['merchants'] as Map<String, dynamic>?;
    final merchantName = merchant?['business_name'] as String? ?? 'Unknown Merchant';
    
    // Get Padala info from delivery_notes if it's a Padala delivery
    String? recipientName;
    String? packageDescription;
    if (isPadala) {
      final deliveryNotes = delivery['delivery_notes'] as String?;
      if (deliveryNotes != null && deliveryNotes.isNotEmpty) {
        try {
          final padalaDetails = Map<String, dynamic>.from(
            const JsonDecoder().convert(deliveryNotes) as Map
          );
          recipientName = padalaDetails['recipient_name'] as String?;
          packageDescription = padalaDetails['package_description'] as String?;
        } catch (e) {
          debugPrint('Error parsing Padala details: $e');
        }
      }
    }
    
    final statusRaw = delivery['status'];
    final status = statusRaw?.toString().toLowerCase() ?? 'pending';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final createdAt = delivery['created_at'] as String?;
    final total = _calculateTotal(delivery);
    final items = delivery['delivery_items'] as List<dynamic>? ?? [];
    final itemCount = items.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          if (isPadala) {
            Navigator.of(context).pushNamed(
              PadalaTrackingPage.routeName,
              arguments: delivery['id'] as String,
            );
          } else {
            Navigator.of(context).pushNamed(
              OrderTrackingPage.routeName,
              arguments: delivery['id'] as String,
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Service type icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isPadala 
                          ? Colors.green.withOpacity(0.1) 
                          : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPadala ? Icons.local_shipping : Icons.restaurant,
                      color: isPadala ? Colors.green : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPadala 
                              ? (recipientName != null ? 'To: $recipientName' : 'Padala Delivery')
                              : merchantName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isPadala && packageDescription != null)
                          Text(
                            packageDescription,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$itemCount item${itemCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...items.take(3).expand<Widget>((item) {
                        final product = item['merchant_products'] as Map<String, dynamic>?;
                        final productName = product?['name'] as String? ?? 'Unknown';
                        final quantity = item['quantity'] as int? ?? 1;
                        final addons = item['delivery_item_addons'] as List<dynamic>? ?? [];
                        
                        return [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Text(
                                  '• ',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                                Expanded(
                                  child: Text(
                                    '$quantity $productName',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Display add-ons for this item
                          ...addons.map<Widget>((addon) {
                            final addonName = addon['name'] as String? ?? 'Unknown';
                            final addonQuantity = addon['quantity'] as int? ?? 1;
                            return Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 4),
                              child: Row(
                                children: [
                                  Text(
                                    '+ ',
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '$addonQuantity $addonName',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ];
                      }).toList(),
                      if (items.length > 3)
                        Text(
                          '... and ${items.length - 3} more',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (delivery['pickup_image'] != null || delivery['dropoff_image'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delivery Photos',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (delivery['pickup_image'] != null)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showFullScreenNetworkImage(
                                  context,
                                  delivery['pickup_image'] as String,
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
                                          delivery['pickup_image'] as String,
                                          height: 80,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            height: 80,
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.image_not_supported,
                                              color: Colors.grey,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.store,
                                              size: 12,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Pickup',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (delivery['dropoff_image'] != null)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showFullScreenNetworkImage(
                                  context,
                                  delivery['dropoff_image'] as String,
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
                                          delivery['dropoff_image'] as String,
                                          height: 80,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            height: 80,
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.image_not_supported,
                                              color: Colors.grey,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.location_on,
                                              size: 12,
                                              color: Colors.red,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Dropoff',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
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
                ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final normalizedStatus = status.toLowerCase().trim();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '₱${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      if (normalizedStatus == 'pending' || 
                          normalizedStatus == 'accepted' ||
                          normalizedStatus == 'assigned' || 
                          normalizedStatus == 'picked_up' || 
                          normalizedStatus == 'picked up' ||
                          normalizedStatus == 'in_transit' ||
                          normalizedStatus == 'in transit' ||
                          normalizedStatus == 'on_the_way' ||
                          normalizedStatus == 'on the way')
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed(
                              OrderTrackingPage.routeName,
                              arguments: delivery['id'] as String,
                            );
                          },
                          icon: const Icon(Icons.location_on, size: 18),
                          label: const Text('Track'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        )
                      else if (normalizedStatus == 'delivered')
                        ElevatedButton.icon(
                          onPressed: () => _markAsCompleted(delivery),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Mark as Completed'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreenNetworkImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
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
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(40),
                    color: Colors.black54,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveriesList(List<Map<String, dynamic>> deliveries, String emptyMessage) {
    if (deliveries.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }

    return RefreshIndicator(
      onRefresh: _loadDeliveries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: deliveries.length,
        itemBuilder: (context, index) {
          return _buildDeliveryCard(deliveries[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Order History'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
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
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDeliveries,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDeliveriesList(
                      _allDeliveries,
                      'No orders yet',
                    ),
                    _buildDeliveriesList(
                      _pendingDeliveries,
                      'No pending orders',
                    ),
                    _buildDeliveriesList(
                      _completedDeliveries,
                      'No completed orders',
                    ),
                    _buildDeliveriesList(
                      _cancelledDeliveries,
                      'No cancelled orders',
                    ),
                  ],
                ),
    );
  }
}

