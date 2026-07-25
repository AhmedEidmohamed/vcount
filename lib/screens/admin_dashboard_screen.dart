import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/counting_service.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String userId;
  final String username;

  const AdminDashboardScreen({
    super.key,
    this.userId = 'admin_id',
    this.username = 'المدير العام',
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0; // 0: الرئيسية (Overview), 1: المستخدمين (Users), 2: التقارير (Reports)
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // زرع البيانات الأولية في Firestore إذا كانت قاعدة البيانات فارغة
    AuthService().seedInitialData();
    // Firestore Streams تتولى التحديث الفوري — لا حاجة لـ polling timer
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _exportDataToExcelCSV(BuildContext context) {
    final List<Map<String, dynamic>> sessions = CountingService().getLocalSessions();

    final StringBuffer csv = StringBuffer();
    // UTF-8 BOM for Microsoft Excel Arabic support
    csv.write('\uFEFF');

    csv.writeln('نظام V-Count - تقرير الرصد الميداني التفصيلي الشامل');
    csv.writeln('تاريخ التصدير,${DateTime.now().toString()}');
    csv.writeln('');

    // Table 1: Session Summaries
    csv.writeln('--- جدول (1): ملخص جلسات العد والرصد الميداني ---');
    csv.writeln(
      'اسم العداد / المشغل,حالة الجلسة,توقيت الفتح (البدء),توقيت القفل (الإنهاء),اسم الموقع والمحطة,إحداثيات Lat,إحداثيات Long,إجمالي المركبات المرصودة,سيارة خاصة,تاكسي,ميكروباص,شاحنة,حافلة,دراجة نارية,دراجة',
    );

    for (var session in sessions) {
      final username = _cleanCsv(session['username'] ?? 'مستخدم ميداني');
      final status = session['status'] == 'active' ? 'نشط 🟢' : 'مكتمل 🏁';
      final openTime = _cleanCsv(session['startTime'] ?? '--');
      final closeTime = session['status'] == 'active' ? 'جارية الآن' : _cleanCsv(session['endTime'] ?? '--');
      final location = _cleanCsv(session['locationName'] ?? 'غير محدد');
      final lat = session['latitude']?.toString() ?? '--';
      final lng = session['longitude']?.toString() ?? '--';
      final total = session['totalCount'] ?? 0;

      final categoryTotalsRaw = session['categoryTotals'];
      Map<String, dynamic> categoryTotals = {};
      if (categoryTotalsRaw is Map) {
        categoryTotals = Map<String, dynamic>.from(categoryTotalsRaw);
      }

      final car = categoryTotals['سيارة خاصة'] ?? 0;
      final taxi = categoryTotals['تاكسي'] ?? 0;
      final microbus = categoryTotals['ميكروباص'] ?? 0;
      final truck = categoryTotals['شاحنة'] ?? 0;
      final bus = categoryTotals['حافلة'] ?? 0;
      final motorcycle = categoryTotals['دراجة نارية'] ?? 0;
      final bicycle = categoryTotals['دراجة'] ?? 0;

      csv.writeln(
        '"$username","$status","$openTime","$closeTime","$location","$lat","$lng",$total,$car,$taxi,$microbus,$truck,$bus,$motorcycle,$bicycle',
      );
    }

    csv.writeln('');
    csv.writeln('--- جدول (2): تفاصيل الرصد دقيقة بدقيقة (Minute-by-Minute Granular Logs) ---');
    csv.writeln(
      'اسم العداد,معرف الجلسة,رقم الدقيقة,توقيت الدقيقة,فئة المركبة المرصودة,العدد المرصود في هذه الدقيقة,موقع الإحداثيات للدقيقة',
    );

    for (var session in sessions) {
      final username = _cleanCsv(session['username'] ?? 'مستخدم ميداني');
      final sessionId = _cleanCsv(session['id'] ?? '');
      final location = _cleanCsv(session['locationName'] ?? 'غير محدد');
      final List minuteLogs = (session['minuteLogs'] is List) ? List.from(session['minuteLogs']) : [];

      for (var log in minuteLogs) {
        final minuteNum = log['minute'] ?? 0;
        final timeCode = log['time'] ?? '';
        final countsRaw = log['counts'];
        if (countsRaw is Map) {
          countsRaw.forEach((catName, countVal) {
            if ((countVal as num) > 0) {
              csv.writeln(
                '"$username","$sessionId",$minuteNum,"$timeCode","${_cleanCsv(catName.toString())}",$countVal,"$location"',
              );
            }
          });
        }
      }
    }

    final csvContent = csv.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.file_download_outlined, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('تصدير بيانات الرصد (Excel)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تم تجهيز ملف إكسيل الشامل (CSV) المتوافق مع Microsoft Excel باللغة العربية.',
                style: TextStyle(fontSize: 12, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'يتضمن التقرير:\n• ملخص لكل عداد والمجموع الكلي للمركبات.\n• أعداد كل مركبة منفصلة (سيارات، تاكسي، موتوسيكلات...).\n• تفاصيل دقيقة بدقيقة لكل تسجيل مع الموقع والإحداثيات.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF475569), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ تم نسخ محتوى ملف Excel (CSV) إلى الحافظة بنجاح!'),
                  backgroundColor: Color(0xFF10B981),
                ),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
            label: const Text('نسخ محتوى Excel (CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _cleanCsv(String val) {
    return val.replaceAll('"', '""').replaceAll('\n', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FE), // خلفية ناصعة ومطابقة للديزاين
      appBar: _buildHeaderAppBar(),
      body: _selectedIndex == 0
          ? _buildDashboardView()
          : _selectedIndex == 1
              ? _buildFieldMonitorView()
              : _buildReportsView(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HEADER APP BAR (مطابق للديزاين: V-Count Pro + Profile Avatar)
  // ══════════════════════════════════════════════════════════════════════════
  PreferredSizeWidget _buildHeaderAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.show_chart_rounded,
                color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 8),
          const Text(
            'V-Count Pro',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () {
            _showLogoutMenu();
          },
          child: Container(
            margin: const EdgeInsets.only(left: 16),
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.accentLight,
              backgroundImage: NetworkImage(
                'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
              ),
              child: Icon(Icons.person, color: AppColors.primaryLight, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  void _showLogoutMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تسجيل الدخول كـ: ${widget.username}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('تسجيل الخروج',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                await AuthService().clearSession();
                AuthService().logActivity(
                  username: widget.username,
                  action: 'تسجيل خروج',
                  role: 'admin',
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0: DASHBOARD OVERVIEW (مطابق تماماً لصفحة الديزاين المرفقة)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDashboardView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subheader: ADMIN CONTROL CENTER / Overview Performance
          Text(
            'ADMIN CONTROL CENTER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryLight.withOpacity(0.9),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ملخص الأداء والعمليات',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 18),

          // Primary CTA Button: + Create New Account (+ إنشاء حساب جديد)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _showCreateUserDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
              label: const Text(
                'إنشاء حساب جديد لليوزر',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8), // أزرق ملكي متألق
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF1D4ED8).withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Stat Cards Stack (TOTAL PERSONNEL, ACTIVE SHIFTS, NEW THIS WEEK)
          _buildStatCard1TotalPersonnel(),
          const SizedBox(height: 14),
          _buildStatCard2ActiveShifts(),
          const SizedBox(height: 14),
          _buildStatCard3NewThisWeek(),
          const SizedBox(height: 24),

          // Section: Recent Accounts (سجل الحسابات الأخيرة)
          const Text(
            'سجل الحسابات الأخيرة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          // Search Input Bar (البحث بالاسم أو ID...)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: const InputDecoration(
                hintText: 'البحث بالاسم، الرقم الوظيفي، أو الموقع...',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                icon: Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                suffixIcon: Icon(Icons.tune_rounded, color: Color(0xFF94A3B8), size: 20),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Recent Accounts Table / List View
          _buildRecentAccountsTable(),
        ],
      ),
    );
  }

  // ── Stat Card 1: TOTAL PERSONNEL (بث مباشر من Firestore) ─────────────────
  Widget _buildStatCard1TotalPersonnel() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AuthService().getUsersStream(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'إجمالي الموظفين والعدّادين',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.groups_rounded,
                        color: Color(0xFF4F46E5), size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.trending_up_rounded, color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 4),
                  Text(
                    'مسجلون في قاعدة البيانات السحابية',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Stat Card 2: ACTIVE SHIFTS (بث مباشر من Firestore) ───────────────────
  Widget _buildStatCard2ActiveShifts() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: CountingService().getActiveSessionsStream(),
      builder: (context, snapshot) {
        final activeCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الورديات النشطة حالياً',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.access_time_filled_rounded,
                        color: Color(0xFF3B82F6), size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$activeCount',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.circle_rounded, color: Color(0xFF2563EB), size: 10),
                  SizedBox(width: 6),
                  Text(
                    'قيد المراقبة والرصد الميداني الآن',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Stat Card 3: NEW THIS WEEK (بث مباشر من Firestore) ───────────────────
  Widget _buildStatCard3NewThisWeek() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AuthService().getUsersStream(),
      builder: (context, snapshot) {
        int newCount = 0;
        if (snapshot.hasData) {
          final now = DateTime.now();
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            final createdAt = data['createdAt'];
            if (createdAt is Timestamp) {
              if (now.difference(createdAt.toDate()).inDays <= 7) newCount++;
            }
          }
        }
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المسجلين الجدد هذا الأسبوع',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.stars_rounded,
                        color: Colors.white, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '+$newCount',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'مسجلون في قاعدة بيانات Firestore',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Recent Accounts Table (بث مباشر من Firestore) ────────────────────────
  Widget _buildRecentAccountsTable() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AuthService().getUsersStream(),
      builder: (context, snapshot) {
        final allUsers = snapshot.hasData
            ? snapshot.data!.docs.map((doc) {
                final data = doc.data();
                return {
                  'id': doc.id,
                  'username': data['username'] ?? '',
                  'name': data['name'] ?? data['username'] ?? '',
                  'password': data['password'] ?? '',
                  'role': data['role'] ?? 'user',
                  'empId': data['empId'] ?? '--',
                  'location': data['location'] ?? 'الميدان',
                  'createdAt': data['createdAt']?.toString() ?? '',
                };
              }).toList()
            : <Map<String, dynamic>>[];

        final filteredUsers = allUsers.where((u) {
          final query = _searchQuery.toLowerCase();
          final name = (u['name'] ?? u['username'] ?? '').toString().toLowerCase();
          final empId = (u['empId'] ?? '').toString().toLowerCase();
          final loc = (u['location'] ?? '').toString().toLowerCase();
          return name.contains(query) || empId.contains(query) || loc.contains(query);
        }).toList();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('الموظف (EMPLOYEE)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B))),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('الرقم (ID)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B))),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('الموقع',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B))),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),

              // Rows
              if (filteredUsers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'لا توجد حسابات مطابقة للبحث',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredUsers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, index) {
                    final u = filteredUsers[index];
                    final String name = u['name'] ?? u['username'] ?? 'مستخدم';
                    final String role = u['role'] == 'admin' ? 'أدمن' : 'مشغّل ميداني';
                    final String empId = u['empId'] ?? 'EMP-8291-2024';
                    final String location = u['location'] ?? 'الميدان الرئيسي';

                    final initials = name.length >= 2
                        ? name.substring(0, 2).toUpperCase()
                        : 'US';

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // Avatar + Name
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: u['role'] == 'admin'
                                        ? const Color(0xFFEDE9FE)
                                        : const Color(0xFFDBEAFE),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: u['role'] == 'admin'
                                            ? const Color(0xFF7C3AED)
                                            : const Color(0xFF2563EB),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        role,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // EMP ID
                          Expanded(
                            flex: 2,
                            child: Text(
                              empId,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),

                          // Location
                          Expanded(
                            flex: 2,
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // Footer
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'عرض ${filteredUsers.length} من إجمالي ${allUsers.length} موظف',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                    const Row(
                      children: [
                        Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                        SizedBox(width: 8),
                        Icon(Icons.chevron_left, size: 18, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1: FIELD MONITOR (البث الميداني الحقيقي من Firestore + الخادم المحلي)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildFieldMonitorView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مراقبة العمليات الميدانية والإحداثيات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'بث مباشر برصد الإحداثيات (Lat & Long) وتفاصيل المركبات لكل مشغّل',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _exportDataToExcelCSV(context),
                icon: const Icon(Icons.file_download_outlined, size: 18, color: Colors.white),
                label: const Text(
                  'تصدير Excel',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: CountingService().getLiveSessionsStream(),
            builder: (context, snapshot) {
              // Firestore هو المصدر الوحيد للحقيقة
              final sessions = snapshot.hasData
                  ? snapshot.data!.docs.map((doc) {
                      final data = doc.data();
                      return {
                        'id': doc.id,
                        ...data,
                      };
                    }).toList()
                  : <Map<String, dynamic>>[];

              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (sessions.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.radar_outlined, size: 48, color: Color(0xFF94A3B8)),
                      SizedBox(height: 12),
                      Text(
                        'لا توجد جلسات عد نشطة حالياً',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'عندما يبدأ أي مستخدم جلسة جديدة ستظهر بياناته هنا فوراً.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  return _buildSessionCard(sessions[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatSessionTime(dynamic timeVal) {
    if (timeVal == null) return 'جارية الآن...';
    if (timeVal is String) {
      final dt = DateTime.tryParse(timeVal);
      if (dt != null) {
        final period = dt.hour >= 12 ? 'م' : 'ص';
        final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        return '${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
      }
      return timeVal;
    }
    if (timeVal is Timestamp) {
      final dt = timeVal.toDate();
      final period = dt.hour >= 12 ? 'م' : 'ص';
      final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      return '${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
    }
    return '--:--';
  }

  Widget _buildSessionCard(Map<String, dynamic> data) {
    final username = data['username'] ?? 'مستخدم ميداني';
    final totalCount = data['totalCount'] ?? 0;
    final locationName = data['locationName'] ?? 'غير محدد';
    final status = data['status'] ?? 'active';
    final double? latitude = (data['latitude'] as num?)?.toDouble();
    final double? longitude = (data['longitude'] as num?)?.toDouble();
    final String latStr = latitude != null ? latitude.toStringAsFixed(6) : '--';
    final String lngStr = longitude != null ? longitude.toStringAsFixed(6) : '--';

    final String openTimeStr = _formatSessionTime(data['startTime']);
    final String closeTimeStr = status == 'active' ? 'جارية الآن 🟢' : _formatSessionTime(data['endTime']);

    final Map<String, dynamic> defaultCategories = {
      'سيارة خاصة': 0,
      'تاكسي': 0,
      'ميكروباص': 0,
      'شاحنة': 0,
      'حافلة': 0,
      'دراجة نارية': 0,
      'دراجة': 0,
    };

    final categoryTotalsRaw = data['categoryTotals'];
    Map<String, dynamic> categoryTotals = Map.from(defaultCategories);
    if (categoryTotalsRaw is Map) {
      categoryTotalsRaw.forEach((k, v) {
        categoryTotals[k.toString()] = v;
      });
    }

    final List minuteLogs = (data['minuteLogs'] is List) ? List.from(data['minuteLogs']) : [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(username,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status == 'active' ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status == 'active' ? 'نشط الآن 🟢' : 'مكتملة 🏁',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: status == 'active' ? const Color(0xFF059669) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // توقيت بدء وإغلاق الجلسة
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
                    const Text('🕒 وقت الفتح/البدء',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(openTimeStr,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  ],
                ),
                Container(width: 1, height: 26, color: const Color(0xFFCBD5E1)),
                Column(
                  children: [
                    const Text('🏁 وقت القفل/الإنهاء',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(closeTimeStr,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: status == 'active' ? const Color(0xFF059669) : const Color(0xFF0F172A))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Text('📍 الموقع: $locationName',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
          const SizedBox(height: 4),
          Text('🌐 Lat: $latStr | Long: $lngStr',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2563EB),
                  fontFamily: 'monospace')),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.directions_car_filled_rounded,
                  size: 20, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 6),
              Text(
                'إجمالي المرصود: $totalCount مركبة',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),

          // فئات المركبات المرصودة لكل نوع
          const SizedBox(height: 12),
          const Text(
            '🚗 الأعداد المُرصودة لكل فئة مركبة بالتفصيل:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: categoryTotals.entries.map((entry) {
              final count = entry.value ?? 0;
              final bool hasCount = (count is num) ? count > 0 : false;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hasCount ? const Color(0xFFDBEAFE) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasCount ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                    width: hasCount ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: hasCount ? FontWeight.w800 : FontWeight.w500,
                        color: hasCount ? const Color(0xFF1E3A8A) : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: hasCount ? const Color(0xFF1D4ED8) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          // تسلسل الرصد دقيقة بدقيقة
          if (minuteLogs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '⏱️ تسلسل الرصد دقيقة بدقيقة (Minute Timeline):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: minuteLogs.map<Widget>((log) {
                    final minuteNum = log['minute'] ?? 0;
                    final timeCode = log['time'] ?? '';
                    final countsRaw = log['counts'];
                    Map<String, dynamic> counts = {};
                    if (countsRaw is Map) {
                      counts = Map<String, dynamic>.from(countsRaw);
                    }

                    final activeEntries = counts.entries
                        .where((e) => (e.value is num) && e.value > 0)
                        .toList();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1D4ED8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'الدقيقة $minuteNum ($timeCode)',
                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (activeEntries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Text(
                                'لا يوجد رصد في هذه الدقيقة',
                                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: activeEntries.map((e) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFBFDBFE)),
                                  ),
                                  child: Text(
                                    '${e.key}: ${e.value}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1E40AF),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2: REPORTS & AUDIT LOGS (بث مباشر من Firestore audit_logs)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildReportsView() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AuthService().getAuditLogsStream(),
      builder: (context, snapshot) {
        final auditLogs = snapshot.hasData
            ? snapshot.data!.docs.map((doc) {
                final data = doc.data();
                return {
                  'id': doc.id,
                  'username': data['username'] ?? '',
                  'role': data['role'] ?? 'user',
                  'action': data['action'] ?? '',
                  'timestamp': data['timestamp'] is Timestamp
                      ? (data['timestamp'] as Timestamp).toDate().toIso8601String()
                      : data['timestamp']?.toString(),
                };
              }).toList()
            : <Map<String, dynamic>>[];

        return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سجل حركات الدخول والخروج والتقارير',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'سجل دائم ومحفوظ لجميع عمليات تسجيل الدخول والخروج والتقارير الميدانية',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _exportDataToExcelCSV(context),
                icon: const Icon(Icons.file_download_outlined, size: 18, color: Colors.white),
                label: const Text(
                  'تصدير Excel',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (auditLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 44, color: Color(0xFF94A3B8)),
                  SizedBox(height: 10),
                  Text(
                    'لا توجد حركات دخول أو خروج مسجلة بعد',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: auditLogs.length,
              itemBuilder: (context, index) {
                final log = auditLogs[index];
                final username = log['username'] ?? 'مستخدم';
                final action = log['action'] ?? 'تسجيل دخول';
                final role = log['role'] ?? 'user';
                final timestampStr = log['timestamp'];

                final isLogin = action.contains('دخول');

                String timeFormatted = '--:--';
                if (timestampStr != null) {
                  final dt = DateTime.tryParse(timestampStr.toString());
                  if (dt != null) {
                    final period = dt.hour >= 12 ? 'م' : 'ص';
                    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                    timeFormatted = '${dt.day}/${dt.month}/${dt.year} - ${hour12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
                  }
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: isLogin ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                        child: Icon(
                          isLogin ? Icons.login_rounded : Icons.logout_rounded,
                          color: isLogin ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  username,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: role == 'admin' ? const Color(0xFFF3E8FF) : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    role == 'admin' ? 'أدمن' : 'عداد',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: role == 'admin' ? const Color(0xFF7C3AED) : const Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeFormatted,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isLogin ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isLogin ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Text(
                          action,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isLogin ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
      }, // end StreamBuilder builder
    ); // end StreamBuilder
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOG: نافذة إنشاء حساب جديد لليوزر (تصلح وتعمل فوراً بكل سهولة)
  // ══════════════════════════════════════════════════════════════════════════
  void _showCreateUserDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'user';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1_rounded,
                      color: Color(0xFF1D4ED8), size: 26),
                  SizedBox(width: 10),
                  Text(
                    'إنشاء حساب جديد لليوزر',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'أدخل اسم المستخدم وكلمة السر المخصصة لتفعيل الحساب فوراً.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),

                  // اسم المستخدم
                  const Text('اسم المستخدم / الاسم:',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      hintText: 'مثال: user1 أو أحمد محمد',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // كلمة السر
                  const Text('كلمة السر:',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'أدخل كلمة السر',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // نوع الحساب
                  const Text('صلاحية الحساب:',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedRole,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'user',
                            child: Text('مستخدم ميداني (عدّاد)',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('أدمن / مدير نظام 👑',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7C3AED))),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedRole = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء',
                      style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final username = usernameController.text.trim();
                          final password = passwordController.text.trim();

                          if (username.isEmpty || password.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى كتابة الاسم وكلمة السر'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          final res = await AuthService().createUser(
                            username: username,
                            password: password,
                            role: selectedRole,
                          );

                          if (!mounted) return;
                          Navigator.pop(context);

                          if (res['success'] == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res['message'] ??
                                    'تم إنشاء الحساب بنجاح'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                            setState(() {}); // تحديث قائمة الجدول فوراً
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res['message'] ?? 'فشل إنشاء الحساب'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('حفظ وإنشاء الحساب',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOTTOM NAVIGATION BAR (مطابق للديزاين المرفق 3 أزرار مع هايلايت)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.grid_view_rounded, 'Dashboard'),
              _navItem(1, Icons.people_outline_rounded, 'Users'),
              _navItem(2, Icons.assessment_outlined, 'Reports'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFDBEAFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
            ),
            const SizedBox(height: 3),
            Text(
              label == 'Dashboard'
                  ? 'الرئيسية'
                  : label == 'Users'
                      ? 'المستخدمين'
                      : 'التقارير',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
