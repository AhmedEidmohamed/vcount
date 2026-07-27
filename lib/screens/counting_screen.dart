import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../services/counting_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

// نموذج بيانات فئة المركبة
class VehicleCategory {
  final String nameAr;
  final String nameEn;
  final IconData icon;
  int count;

  VehicleCategory({
    required this.nameAr,
    required this.nameEn,
    required this.icon,
    this.count = 0,
  });
}

class CountingScreen extends StatefulWidget {
  final String userId;
  final String username;

  const CountingScreen({
    super.key,
    this.userId = 'user_demo',
    this.username = 'مشغّل ميداني',
  });

  @override
  State<CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends State<CountingScreen>
    with TickerProviderStateMixin {
  // حالة الجلسة
  bool _isStarted = false;
  bool _isPaused = false;
  int _sessionTotal = 0;
  final int _targetCount = 220;
  final String _sessionDate = 'اليوم';
  String _elapsed = '00:00:00';

  // معرف الجلسة في Firestore
  String? _currentSessionId;
  int _lastSyncedMinute = 0;

  // التايمر الحقيقي
  Timer? _timer;
  int _secondsElapsed = 0;

  // الموقع والإحداثيات
  String _locationName = 'جاري تحديد الموقع...';
  double? _currentLatitude;
  double? _currentLongitude;
  bool _locationLoading = true;
  bool _locationError = false;
  int _locationRetryCount = 0;

  late AnimationController _pulseController;

  // فئات المركبات
  final List<VehicleCategory> _categories = [
    VehicleCategory(nameAr: 'سيارة خاصة', nameEn: 'Private Car', icon: Icons.directions_car),
    VehicleCategory(nameAr: 'تاكسي', nameEn: 'Taxi', icon: Icons.local_taxi),
    VehicleCategory(nameAr: 'ميكروباص', nameEn: 'Microbus', icon: Icons.airport_shuttle),
    VehicleCategory(nameAr: 'أتوبيس', nameEn: 'Bus', icon: Icons.directions_bus),
    VehicleCategory(nameAr: 'شاحنة خفيفة', nameEn: 'Light Truck', icon: Icons.local_shipping),
    VehicleCategory(nameAr: 'شاحنة', nameEn: 'Heavy Truck', icon: Icons.fire_truck),
    VehicleCategory(nameAr: 'موتوسيكل', nameEn: 'Motorcycle', icon: Icons.two_wheeler),
    VehicleCategory(nameAr: 'توك توك', nameEn: 'Tuk Tuk', icon: Icons.electric_rickshaw),
    VehicleCategory(nameAr: 'دراجة', nameEn: 'Bicycle', icon: Icons.pedal_bike),
  ];

  // تتبع الأعداد التي تم رصدها في الدقيقة الحالية فقط
  final Map<String, int> _currentMinuteCounts = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _recalcTotal();
    _fetchLocation(); // جلب الموقع تلقائياً
  }

  // ─── منطق الموقع ─────────────────────────────────
  Future<void> _fetchLocation() async {
    if (!mounted) return;
    setState(() {
      _locationLoading = true;
      _locationError = false;
      _locationName = 'جاري تحديد الموقع...';
    });

    // الخطوة 1: جرّب GPS الجهاز أولاً
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          final open = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'خدمة الموقع (GPS) مغلقة',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: const Text(
                'يرجى تفعيل خدمة الموقع (GPS) في الهاتف لتحديد موقعك وإحداثياتك بدقة.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('تفعيل GPS'),
                ),
              ],
            ),
          );
          if (open == true) {
            await Geolocator.openLocationSettings();
          }
        }
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      }

      if (serviceEnabled) {
        LocationPermission perm = await Geolocator.checkPermission();

        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }

        if (perm == LocationPermission.deniedForever) {
          if (mounted) {
            final open = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'إذن الموقع مطلوب',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                content: const Text(
                  'يرجى السماح للتطبيق بالوصول إلى الموقع من إعدادات الجهاز.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('فتح الإعدادات'),
                  ),
                ],
              ),
            );
            if (open == true) await Geolocator.openAppSettings();
          }
        }

        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          Position? pos;

          try {
            pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 12),
              ),
            );
          } catch (_) {
            pos = await Geolocator.getLastKnownPosition();
          }

          if (pos != null) {
            _currentLatitude = pos.latitude;
            _currentLongitude = pos.longitude;
            final String coordsStr =
                'Lat: ${pos.latitude.toStringAsFixed(6)}, Long: ${pos.longitude.toStringAsFixed(6)}';

            try {
              final List<Placemark> placemarks = await placemarkFromCoordinates(
                pos.latitude,
                pos.longitude,
              );
              if (placemarks.isNotEmpty && mounted) {
                final p = placemarks.first;
                final List<String> addressParts = [];
                if (p.street != null && p.street!.isNotEmpty)
                  addressParts.add(p.street!);
                if (p.subLocality != null &&
                    p.subLocality!.isNotEmpty &&
                    !addressParts.contains(p.subLocality)) {
                  addressParts.add(p.subLocality!);
                }
                if (p.locality != null &&
                    p.locality!.isNotEmpty &&
                    !addressParts.contains(p.locality)) {
                  addressParts.add(p.locality!);
                }

                final String fullAddress = addressParts.isNotEmpty
                    ? '${addressParts.join("، ")} ($coordsStr)'
                    : coordsStr;

                setState(() {
                  _locationName = fullAddress;
                  _locationLoading = false;
                  _locationError = false;
                  _locationRetryCount = 0;
                });
                return;
              }
            } catch (_) {}

            if (mounted) {
              setState(() {
                _locationName = coordsStr;
                _locationLoading = false;
                _locationError = false;
                _locationRetryCount = 0;
              });
              return;
            }
          }
        }
      }
    } catch (_) {}

    // Fallback عبر IP عند تعذّر الوصول إلى GPS
    await _fetchLocationFromIP();
  }

  Future<void> _fetchLocationFromIP() async {
    try {
      final response = await http
          .get(Uri.parse('https://freeipapi.com/api/json'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final city = data['cityName'] ?? '';
        final region = data['regionName'] ?? '';
        final country = data['countryName'] ?? '';
        final lat = data['latitude'];
        final lng = data['longitude'];

        if (lat != null && lng != null) {
          _currentLatitude = double.tryParse(lat.toString());
          _currentLongitude = double.tryParse(lng.toString());
        }

        final parts = [
          city,
          region,
          country,
        ].where((x) => x.toString().isNotEmpty).toList();
        if (parts.isNotEmpty && mounted) {
          final latStr = _currentLatitude != null
              ? 'Lat: ${_currentLatitude!.toStringAsFixed(6)}'
              : '';
          final lngStr = _currentLongitude != null
              ? 'Long: ${_currentLongitude!.toStringAsFixed(6)}'
              : '';
          final coords = (latStr.isNotEmpty && lngStr.isNotEmpty)
              ? ' ($latStr, $lngStr)'
              : '';

          setState(() {
            _locationName = '${parts.join("، ")}$coords';
            _locationLoading = false;
            _locationError = false;
            _locationRetryCount = 0;
          });
          return;
        }
      }
    } catch (_) {}

    // Fallback 2: ipwho.is
    try {
      final response = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final city = data['city'] ?? '';
        final region = data['region'] ?? '';
        final lat = data['latitude'];
        final lng = data['longitude'];

        if (lat != null && lng != null) {
          _currentLatitude = double.tryParse(lat.toString());
          _currentLongitude = double.tryParse(lng.toString());
        }

        final parts = [
          city,
          region,
        ].where((x) => x.toString().isNotEmpty).toList();
        if (parts.isNotEmpty && mounted) {
          final latStr = _currentLatitude != null
              ? 'Lat: ${_currentLatitude!.toStringAsFixed(6)}'
              : '';
          final lngStr = _currentLongitude != null
              ? 'Long: ${_currentLongitude!.toStringAsFixed(6)}'
              : '';
          final coords = (latStr.isNotEmpty && lngStr.isNotEmpty)
              ? ' ($latStr, $lngStr)'
              : '';

          setState(() {
            _locationName = '${parts.join("، ")}$coords';
            _locationLoading = false;
            _locationError = false;
            _locationRetryCount = 0;
          });
          return;
        }
      }
    } catch (_) {}

    _locationRetryCount++;
    if (_locationRetryCount <= 2 && mounted) {
      await Future.delayed(Duration(seconds: _locationRetryCount * 2));
      if (mounted) {
        await _fetchLocation();
        return;
      }
    }

    if (mounted) {
      setState(() {
        _locationName = 'تعذّر تحديد الموقع الإحداثي';
        _locationLoading = false;
        _locationError = true;
      });
    }
  }

  // ─── منطق التايمر والمزامنة ────────────────────────
  Future<void> _startCountingSession() async {
    _sessionStartTime = DateTime.now();
    try {
      final sessionId = await CountingService()
          .startSession(
            userId: widget.userId,
            username: widget.username,
            latitude: _currentLatitude,
            longitude: _currentLongitude,
            locationName: _locationName,
          )
          .timeout(const Duration(seconds: 3), onTimeout: () => '');

      if (sessionId.isNotEmpty) {
        _currentSessionId = sessionId;
      }
      _lastSyncedMinute = 0;
      _currentMinuteCounts.clear();
    } catch (_) {}
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        setState(() {
          _secondsElapsed++;
          _elapsed = _formatTime(_secondsElapsed);
        });

        // مزامنة كل 30 ثانية واختبار انتقال الفترات
        final currentInterval = (_secondsElapsed ~/ 30) + 1;
        if (currentInterval != _lastSyncedMinute) {
          if (_lastSyncedMinute > 0) {
            _currentMinuteCounts.clear();
          }
          _syncCurrentMinute(currentInterval);
          _lastSyncedMinute = currentInterval;
        }
      }
    });
  }

  void _syncCurrentMinute(int minuteNumber) {
    if (_currentSessionId == null) return;

    final Map<String, int> totals = {
      for (var c in _categories) c.nameAr: c.count,
    };

    CountingService().updateSessionMinuteData(
      sessionId: _currentSessionId!,
      minuteNumber: minuteNumber,
      timeFormatted: _formatTime(_secondsElapsed),
      latitude: _currentLatitude,
      longitude: _currentLongitude,
      locationName: _locationName,
      minuteCounts: Map.from(_currentMinuteCounts),
      categoryTotals: totals,
      totalCount: _sessionTotal,
    );

    // إعادة تعيين رصد الدقيقة التالية
    _currentMinuteCounts.clear();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _stopTimer();
    _pulseController.dispose();
    super.dispose();
  }

  void _recalcTotal() {
    _sessionTotal = _categories.fold(0, (sum, c) => sum + c.count);
  }

  Future<void> _handleLogout() async {
    // 1. وقف التايمر فوراً
    _stopTimer();

    // 2. إنهاء الجلسة وحفظ البيانات لو في جلسة نشطة
    if (_currentSessionId != null) {
      try {
        final totals = {for (var c in _categories) c.nameAr: c.count};
        await CountingService().endSession(
          sessionId: _currentSessionId!,
          totalCount: _sessionTotal,
          categoryTotals: totals,
        );
      } catch (_) {}
    }

    // 3. مسح الجلسة المحفوظة وتسجيل حدث الخروج في السجل
    try {
      await AuthService().clearSession();
      await AuthService().logActivity(
        username: widget.username,
        action: 'تسجيل خروج',
        role: 'user',
      );
    } catch (_) {}

    // 4. التنقل لشاشة الدخول - تأكد إن الـ widget لا يزال مُركّباً
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _syncTotals() {
    if (_currentSessionId == null) {
      _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      CountingService().startSession(
        userId: widget.userId,
        username: widget.username,
        latitude: _currentLatitude,
        longitude: _currentLongitude,
        locationName: _locationName,
      );
    }

    final totals = {for (var c in _categories) c.nameAr: c.count};

    final currentInterval = (_secondsElapsed ~/ 30) + 1;

    CountingService().updateSessionMinuteData(
      sessionId: _currentSessionId!,
      minuteNumber: currentInterval,
      timeFormatted: _formatTime(_secondsElapsed),
      latitude: _currentLatitude,
      longitude: _currentLongitude,
      locationName: _locationName,
      minuteCounts: Map.from(_currentMinuteCounts),
      categoryTotals: totals,
      totalCount: _sessionTotal,
    );
  }

  void _increment(int index) {
    setState(() {
      _categories[index].count++;
      _recalcTotal();
      final catName = _categories[index].nameAr;
      _currentMinuteCounts[catName] = (_currentMinuteCounts[catName] ?? 0) + 1;
    });

    _syncTotals();
  }

  void _decrement(int index) {
    if (_categories[index].count <= 0) return;
    setState(() {
      _categories[index].count--;
      _recalcTotal();
      final catName = _categories[index].nameAr;
      if ((_currentMinuteCounts[catName] ?? 0) > 0) {
        _currentMinuteCounts[catName] = _currentMinuteCounts[catName]! - 1;
      }
    });

    _syncTotals();
  }

  double get _progressPercent => (_sessionTotal / _targetCount).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          _buildSessionSummary(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) => _buildCounterCard(index),
            ),
          ),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.cardBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withOpacity(0.5),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 18,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Text(
                        'M',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MasaratMisr-VCount (${widget.username})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _currentLatitude != null
                              ? 'GPS إحداثيات نشطة'
                              : 'موقع متصل',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _elapsed,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    _isStarted ? 'تسجيل متزامن' : 'جاهز للبدء',
                    style: TextStyle(fontSize: 9, color: AppColors.textLight),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _handleLogout,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEEEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent, width: 1.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'خروج',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionSummary() {
    final latStr = _currentLatitude?.toStringAsFixed(5) ?? '--';
    final lngStr = _currentLongitude?.toStringAsFixed(5) ?? '--';

    return Container(
      color: AppColors.cardBg,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_locationLoading)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.primaryLight,
                  ),
                )
              else if (_locationError)
                const Icon(
                  Icons.location_off_outlined,
                  size: 12,
                  color: Colors.redAccent,
                )
              else
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.primaryLight,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _locationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _locationError
                            ? Colors.redAccent
                            : AppColors.textDark,
                      ),
                    ),
                    if (_currentLatitude != null && _currentLongitude != null)
                      Text(
                        'إحداثيات (Lat: $latStr | Long: $lngStr)',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
              ),
              if (!_locationLoading)
                GestureDetector(
                  onTap: () {
                    _locationRetryCount = 0;
                    _fetchLocation();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _locationError
                          ? Colors.redAccent.withOpacity(0.1)
                          : AppColors.accentLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 11,
                          color: _locationError
                              ? Colors.redAccent
                              : AppColors.primaryLight,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _locationError ? 'إعادة' : 'تحديث GPS',
                          style: TextStyle(
                            fontSize: 9,
                            color: _locationError
                                ? Colors.redAccent
                                : AppColors.primaryLight,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // شريط وقت البدء وحالة الجلسة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.access_time_filled_rounded,
                    size: 13,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'وقت الفتح: ${_isStarted ? _formatTimeOfDay(_sessionStartTime) : "--:--"}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isStarted
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isStarted ? 'نشط الآن 🟢' : 'جاهز للبدء',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isStarted
                        ? const Color(0xFF059669)
                        : AppColors.textLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إجمالي الجلسة',
                    style: TextStyle(fontSize: 10, color: AppColors.textMedium),
                  ),
                  Text(
                    '$_sessionTotal',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(_progressPercent * 100).toInt()}%  ($_sessionTotal/$_targetCount)',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMedium,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _progressPercent,
                        minHeight: 5,
                        backgroundColor: AppColors.accentLight,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // تفصيل أعداد كل مركبة مرصودة
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _categories.map((cat) {
              final hasCount = cat.count > 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasCount
                      ? AppColors.accentLight
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasCount
                        ? AppColors.primaryLight
                        : const Color(0xFFE2E8F0),
                    width: hasCount ? 1.2 : 1.0,
                  ),
                ),
                child: Text(
                  '${cat.nameAr}: ${cat.count}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: hasCount ? FontWeight.w800 : FontWeight.normal,
                    color: hasCount ? AppColors.primary : AppColors.textMedium,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterCard(int index) {
    final cat = _categories[index];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              // اليمين: زر المينص (طرح)
              _counterButton(
                icon: Icons.remove,
                color: AppColors.counterRed,
                bgColor: AppColors.counterRedLight,
                onTap: () => _decrement(index),
              ),

              // المنتصف: أيكونة المركبة واسمها والعدد
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(cat.icon, size: 13, color: AppColors.primaryLight),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            cat.nameEn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        cat.count.toString().padLeft(2, '0'),
                        key: ValueKey(cat.count),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDark,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // الشمال: زر البلص (إضافة)
              _counterButton(
                icon: Icons.add,
                color: AppColors.counterBlue,
                bgColor: AppColors.counterBlueLight,
                onTap: () => _increment(index),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _counterButton({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 32,
        height: 34,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      color: AppColors.cardBg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionBtn(
                    label: 'ابدأ',
                    color: Colors.white,
                    bgColor: AppColors.btnStart,
                    onTap: (!_isStarted)
                        ? () {
                            _stopTimer();
                            setState(() {
                              _isStarted = true;
                              _isPaused = false;
                              _secondsElapsed = 0;
                              _elapsed = '00:00:00';
                            });
                            _startTimer();
                            _startCountingSession();
                          }
                        : null,
                  ),
                  _actionBtn(
                    label: 'إيقاف',
                    color: Colors.white,
                    bgColor: AppColors.btnPause,
                    onTap: (_isStarted && !_isPaused)
                        ? () => setState(() => _isPaused = true)
                        : null,
                  ),
                  _actionBtn(
                    label: 'استئناف',
                    color: Colors.white,
                    bgColor: AppColors.btnResume,
                    onTap: (_isStarted && _isPaused)
                        ? () => setState(() => _isPaused = false)
                        : null,
                  ),
                  _actionBtn(
                    label: 'إنهاء',
                    color: Colors.white,
                    bgColor: AppColors.btnEnd,
                    onTap: _isStarted
                        ? () async {
                            _stopTimer();
                            final String finalTime = _elapsed;

                            if (_currentSessionId != null) {
                              final currentInterval = (_secondsElapsed ~/ 30) + 1;
                              _syncCurrentMinute(currentInterval);

                              final totals = {
                                for (var c in _categories) c.nameAr: c.count,
                              };
                              await CountingService().endSession(
                                sessionId: _currentSessionId!,
                                totalCount: _sessionTotal,
                                categoryTotals: totals,
                              );
                            }

                            setState(() {
                              _isStarted = false;
                              _isPaused = false;
                            });
                            _showEndDialog(finalTime);
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text(
              'تسجيل الخروج',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'هل تريد تسجيل الخروج من الحساب؟\nسيتم حفظ بيانات الجلسة الحالية قبل الخروج.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'إلغاء',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout();
            },
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text(
              'تأكيد الخروج',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required Color color,
    required Color bgColor,
    VoidCallback? onTap,
  }) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: disabled ? AppColors.divider : bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: bgColor.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: disabled ? AppColors.textLight : color,
          ),
        ),
      ),
    );
  }

  DateTime? _sessionStartTime;
  DateTime? _sessionEndTime;

  String _formatTimeOfDay(DateTime? dt) {
    if (dt == null) return '--:--';
    final period = dt.hour >= 12 ? 'م' : 'ص';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  void _showEndDialog(String finalTime) {
    _sessionEndTime = DateTime.now();
    final openTimeStr = _formatTimeOfDay(_sessionStartTime);
    final closeTimeStr = _formatTimeOfDay(_sessionEndTime);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 26,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تم إنهاء ومزامنة الجلسة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إجمالي المركبات المُرصودة: $_sessionTotal',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        '🕒 وقت البدء (الفتح)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        openTimeStr,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 26,
                    color: const Color(0xFFCBD5E1),
                  ),
                  Column(
                    children: [
                      const Text(
                        '🏁 وقت الإنهاء (القفل)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        closeTimeStr,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: AppColors.textMedium,
                ),
                const SizedBox(width: 6),
                Text(
                  'مدة الجلسة: $finalTime',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'الموقع الإحداثي:\n$_locationName',
              style: TextStyle(fontSize: 12, color: AppColors.textMedium),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    color: AppColors.primaryLight,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم إرسال سِجل الدقائق والموقع إلى مركز تحكّم الأدمن بنجاح',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'إغلاق',
              style: TextStyle(
                color: AppColors.textMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
