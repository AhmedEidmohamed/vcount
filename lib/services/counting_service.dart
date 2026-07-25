import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
//  CountingService  —  Firestore هو المصدر الرئيسي الوحيد للبيانات
//  Collections المستخدمة:
//    • counting_sessions  —  جلسات العد الميداني الكاملة
//      └── subcollection: minute_logs  —  سجلات دقيقة بدقيقة لكل جلسة
// ═══════════════════════════════════════════════════════════════════════════
class CountingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── كاش محلي (offline fallback فقط) ──────────────────────────────────
  static const String _cacheSessionsKey = 'vcount_cache_sessions';
  static List<Map<String, dynamic>> _cachedSessions = [];
  static bool _sessionsLoaded = false;

  // =========================================================================
  //  SESSIONS  —  كولكشن: counting_sessions
  // =========================================================================

  /// جلب كل الجلسات من Firestore وتخزينها في الكاش
  Future<void> loadSavedSessions() async {
    try {
      final snap = await _db
          .collection('counting_sessions')
          .orderBy('startTime', descending: true)
          .get()
          .timeout(const Duration(seconds: 5));

      _cachedSessions = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'userId': data['userId'] ?? '',
          'username': data['username'] ?? 'مستخدم ميداني',
          'latitude': data['latitude'],
          'longitude': data['longitude'],
          'locationName': data['locationName'] ?? 'غير محدد',
          'status': data['status'] ?? 'active',
          'startTime': data['startTime'] is Timestamp
              ? (data['startTime'] as Timestamp).toDate().toIso8601String()
              : (data['startTime']?.toString() ?? DateTime.now().toIso8601String()),
          'endTime': data['endTime'] is Timestamp
              ? (data['endTime'] as Timestamp).toDate().toIso8601String()
              : data['endTime']?.toString(),
          'totalCount': data['totalCount'] ?? 0,
          'categoryTotals': Map<String, dynamic>.from(data['categoryTotals'] ?? {}),
          'minuteLogs': List<dynamic>.from(data['minuteLogs'] ?? []),
          'lastUpdated': data['lastUpdated'] is Timestamp
              ? (data['lastUpdated'] as Timestamp).toDate().toIso8601String()
              : data['lastUpdated']?.toString(),
        };
      }).toList();

      _sessionsLoaded = true;
      await _cacheLocally(_cacheSessionsKey, _cachedSessions);
    } catch (e) {
      print('[CountingService] Firestore sessions fetch failed, using local cache: $e');
      await _loadCacheLocally(_cacheSessionsKey, _cachedSessions);
      _sessionsLoaded = true;
    }
  }

  /// بدء جلسة عد جديدة — يُنشئ document في Firestore مباشرةً
  Future<String> startSession({
    required String userId,
    required String username,
    required double? latitude,
    required double? longitude,
    required String locationName,
  }) async {
    final sessionData = {
      'userId': userId,
      'username': username,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'status': 'active',
      'startTime': FieldValue.serverTimestamp(),
      'endTime': null,
      'totalCount': 0,
      'categoryTotals': <String, int>{},
      'minuteLogs': <Map<String, dynamic>>[],
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    try {
      // ── الحفظ المباشر في Firestore ──────────────────────────────────────
      final docRef = await _db
          .collection('counting_sessions')
          .add(sessionData)
          .timeout(const Duration(seconds: 5));

      // إضافة للكاش المحلي بالمعرف الحقيقي من Firestore
      final localEntry = {
        'id': docRef.id,
        'userId': userId,
        'username': username,
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'status': 'active',
        'startTime': DateTime.now().toIso8601String(),
        'endTime': null,
        'totalCount': 0,
        'categoryTotals': <String, dynamic>{},
        'minuteLogs': <dynamic>[],
      };
      _cachedSessions.insert(0, localEntry);
      await _cacheLocally(_cacheSessionsKey, _cachedSessions);

      return docRef.id; // نرجع معرف Firestore مباشرةً
    } catch (e) {
      print('[CountingService] Failed to start session in Firestore: $e');
      // Fallback: إنشاء معرف محلي مؤقت عند انقطاع الشبكة
      final localId = 'local_session_${DateTime.now().millisecondsSinceEpoch}';
      final localEntry = {
        'id': localId,
        'userId': userId,
        'username': username,
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'status': 'active',
        'startTime': DateTime.now().toIso8601String(),
        'endTime': null,
        'totalCount': 0,
        'categoryTotals': <String, dynamic>{},
        'minuteLogs': <dynamic>[],
        '_isLocal': true, // علامة أن هذه الجلسة محلية بانتظار المزامنة
      };
      _cachedSessions.insert(0, localEntry);
      await _cacheLocally(_cacheSessionsKey, _cachedSessions);
      return localId;
    }
  }

  /// تحديث إجماليات الجلسة (عند كل ضغطة عد) — يُحدّث Firestore فوراً
  Future<void> updateSessionTotals({
    required String sessionId,
    required int totalCount,
    required Map<String, int> categoryTotals,
    required double? latitude,
    required double? longitude,
    required String locationName,
  }) async {
    // تحديث الكاش المحلي أولاً (استجابة فورية)
    final index = _cachedSessions.indexWhere((s) => s['id'] == sessionId);
    if (index >= 0) {
      _cachedSessions[index]['totalCount'] = totalCount;
      _cachedSessions[index]['categoryTotals'] = Map<String, dynamic>.from(categoryTotals);
      _cachedSessions[index]['latitude'] = latitude;
      _cachedSessions[index]['longitude'] = longitude;
      _cachedSessions[index]['locationName'] = locationName;
      _cachedSessions[index]['lastUpdated'] = DateTime.now().toIso8601String();
    }

    // التحديث في Firestore (غير معطّل للواجهة)
    _db.collection('counting_sessions').doc(sessionId).update({
      'totalCount': totalCount,
      'categoryTotals': categoryTotals,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'lastUpdated': FieldValue.serverTimestamp(),
    }).catchError((e) {
      print('[CountingService] Failed to update session totals: $e');
    });
  }

  /// تسجيل بيانات دقيقة بدقيقة — يُحدّث Firestore
  Future<void> updateSessionMinuteData({
    required String sessionId,
    required int minuteNumber,
    required String timeFormatted,
    required double? latitude,
    required double? longitude,
    required String locationName,
    required Map<String, int> minuteCounts,
    required Map<String, int> categoryTotals,
    required int totalCount,
  }) async {
    // تحديث الإجماليات أولاً
    await updateSessionTotals(
      sessionId: sessionId,
      totalCount: totalCount,
      categoryTotals: categoryTotals,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
    );

    // بناء سجل الدقيقة
    final minuteEntry = {
      'minute': minuteNumber,
      'time': timeFormatted,
      'timestamp': DateTime.now().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'counts': minuteCounts,
    };

    // تحديث الكاش المحلي
    final index = _cachedSessions.indexWhere((s) => s['id'] == sessionId);
    if (index >= 0) {
      List<dynamic> logs = List.from(_cachedSessions[index]['minuteLogs'] ?? []);
      final existingIndex = logs.indexWhere((l) => l['minute'] == minuteNumber);
      if (existingIndex >= 0) {
        logs[existingIndex] = minuteEntry;
      } else {
        logs.add(minuteEntry);
      }
      _cachedSessions[index]['minuteLogs'] = logs;
      await _cacheLocally(_cacheSessionsKey, _cachedSessions);

      // تحديث minuteLogs في Firestore عبر arrayUnion / set
      _db.collection('counting_sessions').doc(sessionId).update({
        'minuteLogs': logs,
        'lastUpdated': FieldValue.serverTimestamp(),
      }).catchError((e) {
        print('[CountingService] Failed to update minute logs: $e');
      });
    }
  }

  /// إنهاء جلسة العد — يُحدّث الحالة في Firestore
  Future<void> endSession({
    required String sessionId,
    required int totalCount,
    required Map<String, int> categoryTotals,
  }) async {
    // تحديث الكاش
    final index = _cachedSessions.indexWhere((s) => s['id'] == sessionId);
    if (index >= 0) {
      _cachedSessions[index]['status'] = 'completed';
      _cachedSessions[index]['endTime'] = DateTime.now().toIso8601String();
      _cachedSessions[index]['totalCount'] = totalCount;
      _cachedSessions[index]['categoryTotals'] = Map<String, dynamic>.from(categoryTotals);
      await _cacheLocally(_cacheSessionsKey, _cachedSessions);
    }

    // تحديث Firestore
    try {
      await _db.collection('counting_sessions').doc(sessionId).update({
        'status': 'completed',
        'endTime': FieldValue.serverTimestamp(),
        'totalCount': totalCount,
        'categoryTotals': categoryTotals,
        'lastUpdated': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      print('[CountingService] Failed to end session in Firestore: $e');
    }
  }

  /// جلب الجلسات من الكاش المحلي (للعرض السريع)
  List<Map<String, dynamic>> getLocalSessions() => List.from(_cachedSessions);

  /// بث حي لكل الجلسات النشطة والمكتملة (للأدمن داشبورد)
  Stream<QuerySnapshot<Map<String, dynamic>>> getLiveSessionsStream() {
    return _db
        .collection('counting_sessions')
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  /// بث حي للجلسات النشطة فقط
  Stream<QuerySnapshot<Map<String, dynamic>>> getActiveSessionsStream() {
    return _db
        .collection('counting_sessions')
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  // =========================================================================
  //  HELPERS  —  كاش محلي مساعد
  // =========================================================================

  Future<void> _cacheLocally(String key, List<Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadCacheLocally(String key, List<Map<String, dynamic>> target) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        target.clear();
        target.addAll(decoded.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }
}
