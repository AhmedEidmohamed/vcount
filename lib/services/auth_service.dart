import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
//  AuthService  —  Firestore هو المصدر الرئيسي الوحيد للبيانات
//  Collections المستخدمة:
//    • users       — بيانات المستخدمين والموظفين
//    • audit_logs  — سجل دخول وخروج المستخدمين
// ═══════════════════════════════════════════════════════════════════════════
class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── مفاتيح الكاش المحلي (للعمل offline فقط) ──────────────────────────
  static const String _cacheUsersKey = 'vcount_cache_users';
  static const String _cacheAuditKey = 'vcount_cache_audit';

  // ── ذاكرة مؤقتة أثناء الجلسة ─────────────────────────────────────────
  static List<Map<String, dynamic>> _cachedUsers = [];
  static List<Map<String, dynamic>> _cachedAuditLogs = [];
  static bool _usersLoaded = false;

  // =========================================================================
  //  USER MANAGEMENT  —  كولكشن: users
  // =========================================================================

  // ── البيانات الأولية الافتراضية لزرعها في Firestore ───────────────────
  static final List<Map<String, dynamic>> _defaultUsers = [
    {
      'username': 'admin',
      'name': 'المدير العام',
      'password': 'admin123',
      'role': 'admin',
      'empId': 'EMP-8291-2024',
      'location': 'المقر الرئيسي',
    },
    {
      'username': 'adrian',
      'name': 'أدريان مكنزي',
      'password': '123',
      'role': 'user',
      'empId': 'EMP-1001-2024',
      'location': 'بوابة القاهرة الشمالية',
    },
    {
      'username': 'sarah',
      'name': 'سارة لانكستر',
      'password': '123',
      'role': 'admin',
      'empId': 'EMP-1844-2024',
      'location': 'مركز العمليات',
    },
  ];

  /// زرع البيانات الأولية في Firestore إذا كانت قاعدة البيانات فارغة
  Future<void> seedInitialData() async {
    try {
      final snapshot = await _db
          .collection('users')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      // إذا كانت الكولكشن فارغة — ازرع البيانات الافتراضية
      if (snapshot.docs.isEmpty) {
        print('[AuthService] Firestore users collection is empty — seeding initial data...');
        final batch = _db.batch();
        for (final user in _defaultUsers) {
          final docRef = _db.collection('users').doc();
          batch.set(docRef, {
            ...user,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': null,
          });
        }
        await batch.commit();
        print('[AuthService] ✅ Initial users seeded successfully.');
        _usersLoaded = false; // أعد التحميل بعد الزرع
      }
    } catch (e) {
      print('[AuthService] seedInitialData failed: $e');
    }
  }

  /// جلب كل المستخدمين من Firestore وحفظهم في الكاش المحلي
  Future<void> loadSavedUsers({bool forceRefresh = false}) async {
    if (_usersLoaded && !forceRefresh) return;

    try {
      // ── Firestore (المصدر الأساسي) ──────────────────────────────────────
      final snapshot = await _db
          .collection('users')
          .get()
          .timeout(const Duration(seconds: 5));

      _cachedUsers = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'username': data['username'] ?? '',
          'name': data['name'] ?? data['username'] ?? '',
          'password': data['password'] ?? '123',
          'role': data['role'] ?? 'user',
          'empId': data['empId'] ?? 'EMP-0000-0000',
          'location': data['location'] ?? 'الميدان',
          'createdAt': data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate().toIso8601String()
              : (data['createdAt']?.toString() ?? DateTime.now().toIso8601String()),
        };
      }).toList();

      _usersLoaded = true;
      await _cacheLocally(_cacheUsersKey, _cachedUsers); // حفظ كاش محلي
    } catch (e) {
      // ── Fallback: الكاش المحلي عند انقطاع الشبكة ──────────────────────
      print('[AuthService] Firestore users fetch failed, using local cache: $e');
      await _loadCacheLocally(_cacheUsersKey, _cachedUsers);
      _usersLoaded = true;
    }
  }

  /// تسجيل دخول المستخدم — يتحقق من Firestore أولاً ثم الكاش
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    await loadSavedUsers();

    final clean = username.trim().toLowerCase();
    final cleanPwd = password.trim();

    if (clean.isEmpty || cleanPwd.isEmpty) {
      return {'success': false, 'message': 'يرجى إدخال اسم المستخدم وكلمة المرور'};
    }

    // ── 1. الكاش المحلي للسرعة ─────────────────────────────────────────
    final local = _cachedUsers.firstWhere(
      (u) => u['username'].toString().toLowerCase() == clean && u['password'] == cleanPwd,
      orElse: () => {},
    );

    if (local.isNotEmpty) {
      await _recordLoginAudit(local['username'], local['role'] ?? 'user', local['id']);
      return {
        'success': true,
        'message': 'تم تسجيل الدخول بنجاح',
        'userId': local['id'],
        'username': local['username'],
        'name': local['name'],
        'role': local['role'],
      };
    }

    // ── 2. Firestore مباشرةً (في حالة عدم وجوده في الكاش) ──────────────
    try {
      final snap = await _db
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 4));

      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        final data = doc.data();

        if (data['password'] == cleanPwd) {
          // تحديث آخر تسجيل دخول
          _db.collection('users').doc(doc.id).update({
            'lastLogin': FieldValue.serverTimestamp(),
          }).catchError((_) {});

          await _recordLoginAudit(data['username'], data['role'] ?? 'user', doc.id);

          return {
            'success': true,
            'message': 'تم تسجيل الدخول بنجاح',
            'userId': doc.id,
            'username': data['username'],
            'name': data['name'] ?? data['username'],
            'role': data['role'] ?? 'user',
          };
        } else {
          return {'success': false, 'message': 'كلمة المرور غير صحيحة'};
        }
      }
    } catch (e) {
      print('[AuthService] Firestore login check failed: $e');
    }

    return {'success': false, 'message': 'اسم المستخدم غير موجود أو كلمة السر غير صحيحة'};
  }

  /// إنشاء حساب مستخدم جديد وحفظه في Firestore مباشرةً
  Future<Map<String, dynamic>> createUser({
    required String username,
    required String password,
    String role = 'user',
    String? name,
    String? empId,
    String? location,
  }) async {
    final clean = username.trim();
    final cleanPwd = password.trim();

    if (clean.isEmpty || cleanPwd.isEmpty) {
      return {'success': false, 'message': 'يرجى إدخال اسم المستخدم وكلمة المرور'};
    }

    // التحقق من عدم التكرار
    await loadSavedUsers(forceRefresh: true);
    final exists = _cachedUsers.any(
      (u) => u['username'].toString().toLowerCase() == clean.toLowerCase(),
    );
    if (exists) {
      return {'success': false, 'message': 'اسم المستخدم موجود مسبقاً'};
    }

    final userData = {
      'username': clean,
      'name': name ?? clean,
      'password': cleanPwd,
      'role': role,
      'empId': empId ?? 'EMP-${DateTime.now().millisecondsSinceEpoch % 9999}-2024',
      'location': location ?? (role == 'admin' ? 'الإدارة العامة' : 'الميدان'),
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': null,
    };

    try {
      // ── الحفظ المباشر في Firestore ──────────────────────────────────────
      final docRef = await _db
          .collection('users')
          .add(userData)
          .timeout(const Duration(seconds: 5));

      // إعادة تحميل الكاش بعد الإضافة
      await loadSavedUsers(forceRefresh: true);

      return {
        'success': true,
        'message': 'تم إنشاء الحساب بنجاح لـ $clean',
        'userId': docRef.id,
        'username': clean,
      };
    } catch (e) {
      print('[AuthService] Failed to create user in Firestore: $e');
      return {'success': false, 'message': 'فشل إنشاء الحساب: تحقق من الاتصال بالإنترنت'};
    }
  }

  /// حذف مستخدم من Firestore
  Future<bool> deleteUser(String userId) async {
    try {
      await _db.collection('users').doc(userId).delete();
      _cachedUsers.removeWhere((u) => u['id'] == userId);
      await _cacheLocally(_cacheUsersKey, _cachedUsers);
      return true;
    } catch (e) {
      print('[AuthService] Failed to delete user: $e');
      return false;
    }
  }

  /// جلب المستخدمين (من الكاش المحلي للعرض السريع)
  List<Map<String, dynamic>> getLocalUsers() => List.from(_cachedUsers);

  /// بث حي للمستخدمين من Firestore (للأدمن داشبورد)
  Stream<QuerySnapshot<Map<String, dynamic>>> getUsersStream() {
    return _db.collection('users').orderBy('createdAt', descending: true).snapshots();
  }

  // =========================================================================
  //  AUDIT LOGS  —  كولكشن: audit_logs
  // =========================================================================

  /// تسجيل حدث دخول/خروج في Firestore مباشرةً
  Future<void> logActivity({
    required String username,
    required String action,
    String role = 'user',
    String? userId,
  }) async {
    final logEntry = {
      'username': username,
      'role': role,
      'action': action,
      'userId': userId ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      await _db
          .collection('audit_logs')
          .add(logEntry)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      print('[AuthService] Failed to write audit log: $e');
      // حفظ في الكاش المحلي مؤقتاً عند انقطاع الشبكة
      _cachedAuditLogs.insert(0, {
        ...logEntry,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  /// تحميل سجلات الدخول من Firestore
  Future<void> loadSavedAuditLogs() async {
    try {
      final snap = await _db
          .collection('audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 4));

      _cachedAuditLogs = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'username': data['username'] ?? '',
          'role': data['role'] ?? 'user',
          'action': data['action'] ?? '',
          'userId': data['userId'] ?? '',
          'timestamp': data['timestamp'] is Timestamp
              ? (data['timestamp'] as Timestamp).toDate().toIso8601String()
              : (data['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
        };
      }).toList();

      await _cacheLocally(_cacheAuditKey, _cachedAuditLogs);
    } catch (e) {
      print('[AuthService] Audit logs fetch failed, using local cache: $e');
      await _loadCacheLocally(_cacheAuditKey, _cachedAuditLogs);
    }
  }

  /// جلب السجلات (من الكاش المحلي)
  List<Map<String, dynamic>> getAuditLogs() => List.from(_cachedAuditLogs);

  /// بث حي لسجل الدخول (للأدمن داشبورد)
  Stream<QuerySnapshot<Map<String, dynamic>>> getAuditLogsStream() {
    return _db
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  // =========================================================================
  //  HELPERS  —  كاش محلي مساعد
  // =========================================================================

  Future<void> _recordLoginAudit(String username, String role, String userId) async {
    await logActivity(username: username, action: 'تسجيل دخول', role: role, userId: userId);
  }

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
