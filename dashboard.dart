import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:login_form/aboutscreen.dart';
import 'package:login_form/main.dart';
import 'package:login_form/mood_category.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'change_password_screen.dart';
import 'editprofilescreen.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

class DashboardScreen extends StatefulWidget {
  final List<String>? selectedFeatures;

  const DashboardScreen({
    Key? key,
    this.selectedFeatures,
  }) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String username = ''; // Default username
  String userEmail = ''; // Default user email
  File? _imageFile; // User profile picture file
  String? _profileImagePath;
  DateTime? _lastProfileUpdate;
  GoogleMapController? mapController;
  loc.Location _locationController = loc.Location();
  final PanelController _panelController = PanelController();
  DocumentSnapshot<Map<String, dynamic>>? _selectedBar;
  bool _isPanelVisible = false;
  double _panelHeightOpen = 0;
  double _panelHeightClosed = 0;

  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Set<Marker> _markers = {};
  bool _isLoading = false;
  List<String>? _selectedFeatures;
  // Initial camera position (Ipil, Zamboanga Sibugay - centered on downtown)
  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(7.7844, 122.5872), // Ipil downtown coordinates
    zoom: 16, // Adjusted zoom to show more of the town
  );

  // Add this field
  String displayName = '';
  MapType _currentMapType = MapType.normal;

  void onMapCreated(GoogleMapController controller) async {
    setState(() {
      mapController = controller;
    });
    await _loadApprovedBars();
  }

  void _showMapTypeSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Map Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Default'),
              selected: _currentMapType == MapType.normal,
              onTap: () {
                setState(() => _currentMapType = MapType.normal);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.satellite_alt),
              title: const Text('Satellite'),
              selected: _currentMapType == MapType.satellite,
              onTap: () {
                setState(() => _currentMapType = MapType.satellite);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers),
              title: const Text('Hybrid'),
              selected: _currentMapType == MapType.hybrid,
              onTap: () {
                setState(() => _currentMapType = MapType.hybrid);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedFeatures = widget.selectedFeatures;
    loadUserData();
    _setupUserListener();
    getUserLocationUpdates();
    _loadApprovedBars();

    // Initialize panel heights after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _panelHeightOpen = MediaQuery.of(context).size.height * 0.9;
        _panelHeightClosed = 0;
      });
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel(); // Cancel subscription
    super.dispose();
  }

  // Setup real-time user data listener
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;

  void _setupUserListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((DocumentSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.exists) {
          setState(() {
            displayName =
                snapshot.data()?['name'] ?? _formatEmailToName(userEmail);
            username = displayName;

            // Update profile picture if changed
            String? profilePicUrl = snapshot.data()?['profileImagePath'];
            String? lastUpdateStr = snapshot.data()?['profileImageLastUpdated'];

            if (profilePicUrl != null && lastUpdateStr != null) {
              final lastUpdate = DateTime.parse(lastUpdateStr);

              // Only update if we have a new image or if this is a fresh load
              if (_profileImagePath != profilePicUrl ||
                  _lastProfileUpdate == null ||
                  lastUpdate.isAfter(_lastProfileUpdate!)) {
                _profileImagePath = profilePicUrl;
                _lastProfileUpdate = lastUpdate;
                _loadProfilePicture(profilePicUrl);
              }
            }
          });
        }
      });
    }
  }

  Future<void> _loadProfilePicture(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        if (mounted) {
          setState(() => _imageFile = file);
        }
      }
    } catch (e) {
      print('Error loading profile picture: $e');
    }
  }

  // Add method to handle Show All Bars button tap
  Future<void> _launchMapsUrl(LatLng destination, String mode) async {
    final currentLocation = await _getCurrentLocation();
    if (currentLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get your current location')),
        );
      }
      return;
    }

    final origin = '${currentLocation.latitude},${currentLocation.longitude}';
    final dest = '${destination.latitude},${destination.longitude}';
    final modeParam = mode == 'drive'
        ? 'driving'
        : mode == 'motor'
            ? 'driving'
            : 'walking';

    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$dest&travelmode=$modeParam');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw 'Could not launch maps';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps application')),
        );
      }
    }
  }

  Future<LatLng?> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  void _showDirectionsDialog(LatLng destination, String barName) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Get Directions to $barName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_walk),
              title: const Text('Walk there'),
              onTap: () {
                Navigator.pop(context);
                _launchMapsUrl(destination, 'walking');
              },
            ),
            ListTile(
              leading: const Icon(Icons.directions_car),
              title: const Text('Drive there'),
              onTap: () {
                Navigator.pop(context);
                _launchMapsUrl(destination, 'drive');
              },
            ),
            ListTile(
              leading: const Icon(Icons.motorcycle),
              title: const Text('Ride there'),
              onTap: () {
                Navigator.pop(context);
                _launchMapsUrl(destination, 'motor');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  LatLng? _currentPosition;

  void _centerOnUserLocation() async {
    try {
      final loc.LocationData? currentLocation =
          await _locationController.getLocation();
      if (currentLocation != null && mapController != null && mounted) {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target:
                  LatLng(currentLocation.latitude!, currentLocation.longitude!),
              zoom: 15,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get current location'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Reload user data
  void reloadUserData() {
    loadUserData();
  }

  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        userEmail = user.email ?? '';
      });

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          setState(() {
            displayName = userData['name'] ?? _formatEmailToName(userEmail);
            username = displayName;

            // Get profile image path and last update time
            final newProfilePath = userData['profileImagePath'];
            final lastUpdateStr = userData['profileImageLastUpdated'];

            if (newProfilePath != null && lastUpdateStr != null) {
              final lastUpdate = DateTime.parse(lastUpdateStr);

              // Only update if we have a new image or if this is a fresh load
              if (_profileImagePath != newProfilePath ||
                  _lastProfileUpdate == null ||
                  lastUpdate.isAfter(_lastProfileUpdate!)) {
                _profileImagePath = newProfilePath;
                _lastProfileUpdate = lastUpdate;
                _loadProfilePicture(newProfilePath);
              }
            }
          });
        }
      } catch (e) {
        print('Error fetching user data: $e');
        setState(() {
          displayName = _formatEmailToName(userEmail);
          username = displayName;
        });
      }
    }
  }

  String _formatEmailToName(String email) {
    if (email.isEmpty) return '';

    // Get the part before @ symbol
    String namePart = email.split('@')[0];

    // Split by common separators (dots, underscores, numbers)
    List<String> parts = namePart
        .replaceAll(RegExp(r'[0-9]'), ' ')
        .replaceAll('_', ' ')
        .replaceAll('.', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();

    // Capitalize each part
    parts = parts.map((part) {
      if (part.isEmpty) return '';
      return part[0].toUpperCase() + part.substring(1).toLowerCase();
    }).toList();

    // Join the parts with a space
    return parts.join(' ');
  }

  Future<void> getUserLocationUpdates() async {
    bool _serviceEnabled;
    loc.PermissionStatus _permissionGranted;

    _serviceEnabled = await _locationController.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _locationController.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await _locationController.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await _locationController.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    _locationController.onLocationChanged
        .listen((loc.LocationData currentLocation) {
      if (currentLocation.latitude != null &&
          currentLocation.longitude != null) {
        setState(() {
          _currentPosition =
              LatLng(currentLocation.latitude!, currentLocation.longitude!);
        });
        print(_currentPosition);
      }
    });
  }

  void _showBarDetails(DocumentSnapshot<Map<String, dynamic>> bar) {
    setState(() {
      _selectedBar = bar;
      _isPanelVisible = true;
    });
    _panelController.open();
  }

  void _hideBarDetails() {
    _panelController.close();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _selectedBar = null;
          _isPanelVisible = false;
        });
      }
    });
  }

  Widget _buildBarDetailsPanel() {
    if (_selectedBar == null) return const SizedBox.shrink();

    final data = _selectedBar!.data()!;
    final Map<String, dynamic> operatingHours = data['operatingHours'] as Map<String, dynamic>? ?? {};
    final List<dynamic> features = data['features'] as List<dynamic>? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 2,
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _hideBarDetails,
                  ),
                ),
                // Bar content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bar Image
                      if (data['profileImagePath'] != null)
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: NetworkImage(data['profileImagePath'] as String),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Bar Name
                      Text(
                        data['barName'] as String? ?? 'Unknown Bar',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Handlee',
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Rating and Review Count
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${(data['rating'] as num? ?? 0.0).toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${data['reviewCount'] as int? ?? 0} reviews)',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Description
                      Text(
                        data['description'] as String? ?? 'No description available',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Address
                      _buildInfoRow(
                        Icons.location_on,
                        [
                          data['streetAddress'] as String?,
                          data['barangay'] as String?,
                          data['municipality'] as String?,
                          data['province'] as String?,
                        ].where((s) => s != null && s.isNotEmpty).join(', '),
                      ),
                      const SizedBox(height: 16),
                      // Operating Hours
                      _buildOperatingHours(operatingHours),
                      const SizedBox(height: 16),
                      // Contact Number
                      _buildInfoRow(
                        Icons.phone,
                        data['contactNumber'] as String? ?? 'No contact number available',
                      ),
                      const SizedBox(height: 16),
                      // Features
                      if (features.isNotEmpty) ...[
                        const Text(
                          'Features',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: features.map((feature) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                feature.toString(),
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Get Directions Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (data['location'] != null) {
                              final GeoPoint geoPoint = data['location'] as GeoPoint;
                              final LatLng location = LatLng(
                                geoPoint.latitude,
                                geoPoint.longitude,
                              );
                              _showDirectionsDialog(location, data['barName'] as String? ?? '');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Get Directions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
    );
  }

  Widget _buildOperatingHours(Map<String, dynamic> hours) {
    if (hours.isEmpty) return _buildInfoRow(Icons.access_time, 'Hours not specified');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.access_time, color: Colors.grey[600], size: 20),
            const SizedBox(width: 8),
            Text(
              'Operating Hours',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].map((day) {
          final schedule = hours[day.toLowerCase()] as Map<String, dynamic>?;
          if (schedule == null) return const SizedBox.shrink();
          
          return Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    day.substring(0, 3), // Show first 3 letters of day
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    schedule['closed'] == true 
                        ? 'Closed'
                        : '${schedule['open'] ?? 'N/A'} - ${schedule['close'] ?? 'N/A'}',
                    style: TextStyle(
                      color: schedule['closed'] == true ? Colors.red : Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadApprovedBars() async {
    setState(() => _isLoading = true);
    try {
      // Get all approved bars from Firestore with proper typing
      final QuerySnapshot<Map<String, dynamic>> barSnapshot = await _firestore
          .collection('bars')
          .where('status', isEqualTo: 'approved')
          .withConverter<Map<String, dynamic>>(
            fromFirestore: (snapshot, _) => snapshot.data() ?? {},
            toFirestore: (data, _) => data,
          )
          .get();

      setState(() {
        _markers.clear();

        // Add markers for each bar
        for (var doc in barSnapshot.docs) {
          final data = doc.data();
          
          // Skip bars that don't match the selected features
          if (_selectedFeatures != null && _selectedFeatures!.isNotEmpty) {
            final List<dynamic> barFeatures = data['features'] as List<dynamic>? ?? [];
            bool hasMatchingFeature = false;
            
            // Check if the bar has at least one of the selected features
            for (String feature in _selectedFeatures!) {
              if (barFeatures.contains(feature)) {
                hasMatchingFeature = true;
                break;
              }
            }
            
            // Skip this bar if it doesn't have any matching features
            if (!hasMatchingFeature) continue;
          }

          // Get bar location
          final location = data['location'];
          if (location != null) {
            final GeoPoint geoPoint = location as GeoPoint;
            final LatLng position = LatLng(geoPoint.latitude, geoPoint.longitude);

            _markers.add(
              Marker(
                markerId: MarkerId(doc.id),
                position: position,
                infoWindow: InfoWindow(
                  title: data['barName'] as String? ?? 'Unknown Bar',
                  snippet: data['description'] as String? ?? '',
                ),
                onTap: () => _showBarDetails(doc),
              ),
            );
          }
        }
        _isLoading = false;
      });

      // Adjust map to show all markers
      if (_markers.isNotEmpty && mapController != null) {
        _fitBoundsForMarkers();
      }
    } catch (e) {
      print('Error loading bars: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
              _logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: ${e.toString()}')),
        );
      }
    }
  }

  Widget buildProfileImage() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: _imageFile != null
            ? Image.file(
                _imageFile!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _defaultProfileImage();
                },
              )
            : _defaultProfileImage(),
      ),
    );
  }

  Widget _defaultProfileImage() {
    return Container(
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: 40,
        color: Colors.grey[600],
      ),
    );
  }

  LatLngBounds _getBounds(Set<Marker> markers) {
    if (markers.isEmpty) {
      return LatLngBounds(
        southwest: const LatLng(7.7844, 122.5872),
        northeast: const LatLng(7.7844, 122.5872),
      );
    }

    double minLat = markers.first.position.latitude;
    double maxLat = markers.first.position.latitude;
    double minLng = markers.first.position.longitude;
    double maxLng = markers.first.position.longitude;

    for (Marker marker in markers) {
      if (marker.position.latitude < minLat) minLat = marker.position.latitude;
      if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
      if (marker.position.longitude < minLng) minLng = marker.position.longitude;
      if (marker.position.longitude > maxLng) maxLng = marker.position.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat - 0.01, minLng - 0.01),
      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
    );
  }

  void _fitBoundsForMarkers() {
    final bounds = _getBounds(_markers);
    mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isPanelVisible) {
          _hideBarDetails();
          return false;
        }
        return true;
      },
      child: Scaffold(
        key: _scaffoldKey,
        body: SlidingUpPanel(
          controller: _panelController,
          minHeight: 0,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          defaultPanelState: PanelState.CLOSED,
          backdropEnabled: true,
          backdropOpacity: 0.5,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          onPanelClosed: () {
            if (_isPanelVisible) {
              _hideBarDetails();
            }
          },
          panel: _buildBarDetailsPanel(),
          body: Stack(
            children: [
              // Map View
              GoogleMap(
                onMapCreated: (controller) {
                  setState(() => mapController = controller);
                },
                initialCameraPosition: _kGooglePlex,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                markers: _markers,
                mapType: _currentMapType,
                zoomControlsEnabled: false,
                buildingsEnabled: true,
                trafficEnabled: true,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                mapToolbarEnabled:
                    true, // Enable the default toolbar for directions
                compassEnabled: false,
              ),
              if (_isLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),

              // Search Bar
              Positioned(
                top: 40,
                left: 16,
                right: 16,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search here',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16),
                          ),
                          //          onChanged: _onSearch,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.mic),
                          onPressed: () {
                            // Implement voice search
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Layer Button
              Positioned(
                top: 120,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.layers),
                    onPressed: _showMapTypeSelector,
                  ),
                ),
              ),

              // Location Button
              Positioned(
                right: 16,
                bottom: 120,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.my_location),
                    onPressed: _centerOnUserLocation,
                  ),
                ),
              ),

              // Bottom Navigation
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavButton(
                        true,
                        'Explore',
                        Icons.explore,
                      ),
                      _buildNavButton(
                        false,
                        'Commute',
                        Icons.home_work,
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
        drawer: _buildDrawer(),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
        child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.only(top: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color.fromARGB(255, 0, 0, 0),
                  const Color.fromARGB(255, 255, 255, 255),
                ],
              ),
            ),
            child: UserAccountsDrawerHeader(
              margin: EdgeInsets.zero,
              decoration: const BoxDecoration(
                color: Color.fromARGB(0, 196, 24, 24),
              ),
              accountName: Text(
                displayName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              accountEmail: Text(
                userEmail,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              currentAccountPicture: Hero(
                tag: 'profile_picture',
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _imageFile != null
                        ? Image.file(
                            _imageFile!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _defaultProfileImage();
                            },
                          )
                        : _defaultProfileImage(),
                  ),
                ),
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.person),
            title: Text('Edit Profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditProfileScreen(
                    onProfileUpdated: loadUserData,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.lock),
            title: Text('Change Password'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChangePasswordScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.mood),
            title: Text('Change Mood Preference'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MoodCategoryScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.book_sharp),
            title: Text('About'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AboutScreen(),
                ),
              );
            },
          ),
          Divider(),
          ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text('Logout'),
              onTap: () => _showLogoutConfirmation(
                    context,
                  )),
        ],
      ),
    ));
  }
}

Widget _buildNavButton(bool isSelected, String label, IconData icon) {
  final color = isSelected ? Colors.blue : Colors.grey;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        color: color,
        size: 24,
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    ],
  );
}