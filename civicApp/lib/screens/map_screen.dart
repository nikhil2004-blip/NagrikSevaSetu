// lib/screens/map_screen.dart
// ─────────────────────────────────────────────────────────────
// Map Screen — Shows all civic complaints as Google Maps markers
//
// Features:
//   - Color-coded markers by status (orange=pending, blue=in progress, green=resolved)
//   - Auto-pans to user's current location on load
//   - Tapping a marker shows a bottom sheet with complaint details
//   - Legend overlay shows marker color meanings
//   - Re-center FAB for quick navigation
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/complaint_provider.dart';
import '../widgets/upvote_button.dart';
import '../services/location_service.dart';
import '../models/complaint.dart';

// ── Bangalore city center — default starting position
const _kBangaloreLatLng = LatLng(12.9716, 77.5946);
const _kDefaultZoom = 12.0;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  bool _showLegend = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ComplaintProvider>();
      if (provider.allComplaints.isEmpty) {
        provider.loadAllComplaints().then((_) => _panToUserLocation());
      } else {
        _panToUserLocation();
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _panToUserLocation() async {
    if (_mapController == null) return;
    try {
      final pos = await LocationService().getCurrentLocation();
      if (!mounted) return;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: _kDefaultZoom,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed to get user location: $e');
    }
  }

  void _showComplaintBottomSheet(Complaint complaint) {
    final statusColor = _getStatusColor(complaint.status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category + badges row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getCategoryIcon(complaint.category),
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            complaint.category,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildBadge(complaint.status, statusColor),
                        _buildBadge(
                          '${complaint.upvotes} upvotes',
                          Colors.grey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Description
                    Text(
                      complaint.description.isNotEmpty
                          ? complaint.description
                          : '(Voice note complaint)',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),

                    // Voice transcript
                    if (complaint.voiceNoteTranscript != null &&
                        complaint.voiceNoteTranscript!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.mic_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                complaint.voiceNoteTranscript!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Image
                    if (complaint.imageUrl != null) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          complaint.imageUrl!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],

                    // Upvote button
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Spacer(),
                        UpvoteButton(complaintId: complaint.id),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Complaints Map'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.layers_rounded),
            tooltip: 'Toggle legend',
            onPressed: () => setState(() => _showLegend = !_showLegend),
          ),
        ],
      ),
      body: Stack(
        children: [
          Consumer<ComplaintProvider>(
            builder: (context, provider, _) {
              if (provider.isLoadingAll) {
                return const Center(child: CircularProgressIndicator());
              }

              final complaints = provider.allComplaints;

              final markers = complaints.map((c) {
                return Marker(
                  markerId: MarkerId(c.id),
                  position: LatLng(c.lat, c.lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      _getMarkerHueForStatus(c.status)),
                  infoWindow: InfoWindow(
                    title: '${c.category} — ${c.status}',
                    snippet: c.description.length > 60
                        ? '${c.description.substring(0, 57)}...'
                        : c.description,
                  ),
                  onTap: () => _showComplaintBottomSheet(c),
                );
              }).toSet();

              return GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _kBangaloreLatLng,
                  zoom: _kDefaultZoom,
                ),
                markers: markers,
                myLocationButtonEnabled: false,
                myLocationEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (complaints.isNotEmpty) {
                    _panToUserLocation();
                  }
                },
              );
            },
          ),

          // ── Legend Overlay ─────────────────────────────────────
          if (_showLegend)
            Positioned(
              bottom: 88,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildLegendItem(const Color(0xFFF59E0B), 'Pending'),
                    const SizedBox(height: 4),
                    _buildLegendItem(const Color(0xFF3B82F6), 'In Progress'),
                    const SizedBox(height: 4),
                    _buildLegendItem(const Color(0xFF10B981), 'Resolved'),
                    const SizedBox(height: 4),
                    _buildLegendItem(const Color(0xFFEF4444), 'Rejected'),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _panToUserLocation,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.my_location_rounded,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────
  
  double _getMarkerHueForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return BitmapDescriptor.hueOrange;
      case 'in progress':
      case 'in_progress':
        return BitmapDescriptor.hueAzure;
      case 'resolved':
        return BitmapDescriptor.hueGreen;
      case 'rejected':
        return BitmapDescriptor.hueRed;
      default:
        return BitmapDescriptor.hueYellow;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'in progress':
      case 'in_progress':
        return const Color(0xFF3B82F6);
      case 'resolved':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'sanitation':
        return Icons.cleaning_services_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'electrical':
        return Icons.electrical_services_rounded;
      case 'road':
        return Icons.route_rounded;
      default:
        return Icons.report_problem_rounded;
    }
  }
}

