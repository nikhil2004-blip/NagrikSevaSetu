// lib/screens/home_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/complaint_provider.dart';
import '../services/location_service.dart';
import '../models/complaint.dart';
import 'submit_complaint.dart';
import 'complaint_status.dart';
import 'map_screen.dart';
import 'notifications_screen.dart';
import '../widgets/complaint_card.dart';
import '../widgets/category_card.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _headerAnimationController;
  late AnimationController _categoriesAnimationController;
  late AnimationController _complaintsAnimationController;
  late Animation<double> _headerSlideAnimation;
  late Animation<double> _categoriesSlideAnimation;
  late Animation<double> _complaintsSlideAnimation;
  late Animation<double> _headerFadeAnimation;
  late Animation<double> _categoriesFadeAnimation;
  late Animation<double> _complaintsFadeAnimation;

  final LocationService _locationService = LocationService();
  Position? _currentPosition;
  bool _isRestoring = true;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkLostCameraData();
  }

  Future<void> _fetchUserLocation() async {
    try {
      Position pos = await _locationService.getCurrentLocation();
      setState(() {
        _currentPosition = pos;
      });
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _checkLostCameraData() async {
    try {
      final picker = ImagePicker();
      final response = await picker.retrieveLostData();

      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('pending_complaint') ?? false;

      if (pending) {
        final savedCategory = prefs.getString('pending_category') ?? 'Others';
        final savedDesc = prefs.getString('pending_desc');

        // Clear immediately so it doesn't trigger again
        await prefs.remove('pending_complaint');
        await prefs.remove('pending_category');
        await prefs.remove('pending_desc');

        if (!response.isEmpty && response.file != null && mounted) {
          // Push user directly back into the complaint form without a visual jump
          await Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, _, _) => SubmitComplaintScreen(
                initialCategory: savedCategory,
                recoveredDesc: savedDesc,
                recoveredImage: File(response.file!.path),
              ),
              transitionDuration: Duration.zero,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error recovering lost camera data: $e');
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
        _startAnimations();
        _fetchUserLocation();
        context.read<ComplaintProvider>().loadAllComplaints();
      }
    }
  }

  double _calculateDistance(Complaint c) {
    if (_currentPosition == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      c.lat,
      c.lng,
    );
  }

  List<Complaint> _sortComplaintsByDistance(List<Complaint> complaints) {
    final sorted = List<Complaint>.from(complaints);
    sorted.sort(
      (a, b) => _calculateDistance(a).compareTo(_calculateDistance(b)),
    );
    return sorted;
  }

  void _setupAnimations() {
    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _categoriesAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _complaintsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _headerSlideAnimation = Tween<double>(begin: -50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _headerAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _categoriesSlideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _categoriesAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _complaintsSlideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _complaintsAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _headerFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _headerAnimationController,
        curve: Curves.easeOut,
      ),
    );

    _categoriesFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _categoriesAnimationController,
        curve: Curves.easeOut,
      ),
    );

    _complaintsFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _complaintsAnimationController,
        curve: Curves.easeOut,
      ),
    );
  }

  void _startAnimations() async {
    await _headerAnimationController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _categoriesAnimationController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _complaintsAnimationController.forward();
  }

  @override
  void dispose() {
    _headerAnimationController.dispose();
    _categoriesAnimationController.dispose();
    _complaintsAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoring) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const Center(
          // Minimal spinner to look natural while loading image from OS
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () => context.read<ComplaintProvider>().loadAllComplaints(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildModernAppBar(context),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeHeader(),
                  const SizedBox(height: 32),
                  _buildCategoriesSection(),
                  const SizedBox(height: 40),
                  _buildComplaintsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
      drawer: _buildModernDrawer(context),
    );
  }

  Widget _buildModernAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      leading: Builder(
        builder: (BuildContext innerContext) {
          return IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            onPressed: () => Scaffold.of(innerContext).openDrawer(),
          );
        },
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeHeader() {
    final authProvider = context.watch<AuthProvider>();
    final userName =
        authProvider.userProfile?.name ??
        authProvider.firebaseUser?.displayName ??
        'Citizen';
    final firstName = userName.split(' ').first;
    final greeting = _getTimeGreeting();

    return AnimatedBuilder(
      animation: _headerAnimationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _headerSlideAnimation.value),
          child: Opacity(
            opacity: _headerFadeAnimation.value,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting,',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    firstName,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Report issues in your area',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildCategoriesSection() {
    return AnimatedBuilder(
      animation: _categoriesAnimationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _categoriesSlideAnimation.value),
          child: Opacity(
            opacity: _categoriesFadeAnimation.value,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildAnimatedCategoryCard(
                        'Sanitation',
                        Icons.cleaning_services_rounded,
                        0,
                      ),
                      _buildAnimatedCategoryCard(
                        'Water',
                        Icons.water_drop_rounded,
                        1,
                      ),
                      _buildAnimatedCategoryCard(
                        'Electrical',
                        Icons.electrical_services_rounded,
                        2,
                      ),
                      _buildAnimatedCategoryCard(
                        'Road',
                        Icons.route_rounded,
                        3,
                      ),
                      _buildAnimatedCategoryCard(
                        'Others',
                        Icons.more_horiz_rounded,
                        4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedCategoryCard(String category, IconData icon, int index) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 600 + (index * 100)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: CategoryCard(
            category: category,
            icon: icon,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      SubmitComplaintScreen(initialCategory: category),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        return SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(1.0, 0.0),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: child,
                        );
                      },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildComplaintsSection() {
    return AnimatedBuilder(
      animation: _complaintsAnimationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _complaintsSlideAnimation.value),
          child: Opacity(
            opacity: _complaintsFadeAnimation.value,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Reports',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ComplaintStatusScreen(),
                            ),
                          );
                        },
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Use Consumer to listen to ComplaintProvider state
                Consumer<ComplaintProvider>(
                  builder: (context, provider, _) {
                    if (provider.isLoadingAll) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (provider.errorMessage != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                provider.errorMessage!,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: Colors.red.shade600),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => provider.loadAllComplaints(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final complaints = provider.allComplaints;
                    if (complaints.isEmpty) {
                      return _buildEmptyState();
                    }

                    // Just sort all complaints by distance (nearest first)
                    final sortedComplaints = _sortComplaintsByDistance(
                      complaints,
                    );

                    return Column(
                      children: sortedComplaints.asMap().entries.map((e) {
                        int index = e.key;
                        Complaint complaint = e.value;
                        return TweenAnimationBuilder<double>(
                          duration: Duration(
                            milliseconds: 300 + (index * 50),
                          ), // slightly faster stagger
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: ComplaintCard(complaint: complaint),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.campaign_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No reports yet',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to report a civic issue\nin your area and make a difference!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const SubmitComplaintScreen(initialCategory: 'Others'),
                ),
              );
            },
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Report an Issue'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final firebaseUser = authProvider.firebaseUser;
    final userProfile = authProvider.userProfile;

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // ── Drawer Header with User Profile ──────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 24,
              left: 20,
              right: 20,
              bottom: 24,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User avatar — Google profile photo or fallback initial
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: firebaseUser?.photoURL != null
                        ? Image.network(
                            firebaseUser!.photoURL!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildAvatarFallback(userProfile?.name ?? 'U'),
                          )
                        : _buildAvatarFallback(userProfile?.name ?? 'U'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  userProfile?.name ?? firebaseUser?.displayName ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  firebaseUser?.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'नागरिक सेवा सेतु',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // ── Nav Items ────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _buildDrawerItem(
                    context,
                    icon: Icons.home_rounded,
                    title: 'Home',
                    onTap: () => Navigator.pop(context),
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.receipt_long_rounded,
                    title: 'My Complaints',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ComplaintStatusScreen(),
                        ),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.map_rounded,
                    title: 'Map View',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MapScreen()),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    context,
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  _buildDrawerItem(
                    context,
                    icon: Icons.logout_rounded,
                    title: 'Sign Out',
                    onTap: () {
                      Navigator.pop(context);
                      context.read<AuthProvider>().signOut();
                    },
                    isDestructive: true,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          color: isDestructive
              ? Colors.red.shade400
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDestructive
                ? Colors.red.shade400
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Container(
      width: 64,
      height: 64,
      color: Colors.white.withOpacity(0.2),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
