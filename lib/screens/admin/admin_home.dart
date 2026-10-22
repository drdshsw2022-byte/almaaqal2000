import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/profile_sheet.dart';
import '../common/reports_screen.dart';
import '../doctor/doctor_home.dart';
import 'courses_screen.dart';
import 'dashboard_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'staff_screen.dart';
import 'structure_screen.dart';
import 'students_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  bool _loading = true;
  bool _seeded = true;
  int _students = 0, _doctors = 0, _courses = 0, _depts = 0, _today = 0;
  List<LectureSession> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _seeded = await repo.isSeeded();
      final r = await Future.wait([
        repo.students(),
        repo.staff(),
        repo.courses(),
        repo.departments(),
        repo.recentSessions(limit: 30),
      ]);
      final scope = AppState.scope;
      _students = (r[0] as List<Student>)
          .where((x) => scope.isAll || scope.hasDept(x.deptId))
          .length;
      _doctors = (r[1] as List<Staff>)
          .where((x) =>
              (x.role == 'doctor' || x.role == 'head') && scope.hasDept(x.deptId))
          .length;
      _courses =
          (r[2] as List<Course>).where((c) => scope.hasDept(c.deptId)).length;
      _depts = scope.filterDepts(r[3] as List<Department>).length;
      _recent = (r[4] as List<LectureSession>)
          .where((x) => scope.hasDept(x.deptId))
          .toList();
      final now = DateTime.now();
      _today = _recent
          .where((s) =>
              s.startTime.year == now.year &&
              s.startTime.month == now.month &&
              s.startTime.day == now.day)
          .length;
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _seed() async {
    final ok = await confirmDialog(
        context,
        'تهيئة قاعدة البيانات',
        'سيتم رفع بيانات الكليات والأقسام (3) والمواد (136) والطلاب (538) من الملفات المرفقة بالتطبيق. لن تُحذف أي بيانات موجودة.',
        ok: 'ابدأ التهيئة');
    if (!ok || !mounted) return;
    final progress = ValueNotifier<String>('...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 18),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, v, __) => Text(v),
              ),
            ),
          ],
        ),
      ),
    );
    try {
      await repo.seedFromAssets((m) => progress.value = m);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showSnack(context, 'تمت تهيئة قاعدة البيانات بنجاح');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showSnack(context, friendlyError(e), error: true);
      }
    }
    _load();
  }

  void _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = AppState.user.value!;
    final p = AppColors.tilePalette;
    final role = user.role;
    final top = role == Role.admin || role == Role.president;
    final teaches = (role == Role.head || role == Role.dean) &&
        user.staff!.courseIds.isNotEmpty;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              title: user.name,
              subtitle:
                  '${roleName(user.staff!.role)} • ${termName(AppState.settings.currentTerm)}',
              roleIcon: switch (role) {
                Role.president => Icons.account_balance_rounded,
                Role.dean => Icons.domain_rounded,
                Role.head => Icons.apartment_rounded,
                _ => Icons.admin_panel_settings,
              },
              actions: [
                IconButton(
                  onPressed: () => showProfileSheet(context),
                  icon: const Icon(Icons.account_circle_outlined,
                      color: Colors.white),
                ),
                IconButton(
                  onPressed: () => logout(context),
                  icon: const Icon(Icons.logout, color: Colors.white),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_loading && !_seeded && top) _seedCard(),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.1,
                    children: [
                      StatCard(
                          label: 'الطلاب',
                          value: _loading ? '…' : '$_students',
                          icon: Icons.groups_rounded,
                          gradient: p[0]),
                      StatCard(
                          label: 'التدريسيون',
                          value: _loading ? '…' : '$_doctors',
                          icon: Icons.co_present_rounded,
                          gradient: p[1]),
                      StatCard(
                          label: 'المواد / الأقسام',
                          value: _loading ? '…' : '$_courses / $_depts',
                          icon: Icons.menu_book_rounded,
                          gradient: p[2]),
                      StatCard(
                          label: 'محاضرات اليوم',
                          value: _loading ? '…' : '$_today',
                          icon: Icons.qr_code_2_rounded,
                          gradient: p[3]),
                    ],
                  ),
                  const SectionTitle('الإدارة'),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.92,
                    children: [
                      ActionTile(
                          title: 'المؤشرات',
                          subtitle: 'لوحة حية',
                          icon: Icons.dashboard_rounded,
                          gradient: p[7],
                          onTap: () => _open(const DashboardScreen())),
                      ActionTile(
                          title: 'رفع Excel',
                          subtitle: 'إدخال البيانات',
                          icon: Icons.upload_file_rounded,
                          gradient: p[3],
                          onTap: () => _open(const ImportScreen())),
                      if (top)
                        ActionTile(
                            title: 'الكليات',
                            subtitle: 'والأقسام',
                            icon: Icons.account_balance_rounded,
                            gradient: p[6],
                            onTap: () => _open(const StructureScreen())),
                      ActionTile(
                          title: 'المواد',
                          subtitle: 'الدراسية',
                          icon: Icons.auto_stories_rounded,
                          gradient: p[2],
                          onTap: () => _open(const CoursesScreen())),
                      ActionTile(
                          title: 'الطلاب',
                          subtitle: 'والأقسام',
                          icon: Icons.school_rounded,
                          gradient: p[0],
                          onTap: () => _open(const StudentsScreen())),
                      ActionTile(
                          title: 'الكادر',
                          subtitle: 'الهيئة التدريسية',
                          icon: Icons.badge_rounded,
                          gradient: p[1],
                          onTap: () => _open(const StaffScreen())),
                      ActionTile(
                          title: 'التقارير',
                          subtitle: 'الحضور والغياب',
                          icon: Icons.insights_rounded,
                          gradient: p[4],
                          onTap: () => _open(const ReportsScreen())),
                      if (teaches)
                        ActionTile(
                            title: 'محاضراتي',
                            subtitle: 'تسجيل الحضور',
                            icon: Icons.qr_code_scanner_rounded,
                            gradient: p[5],
                            onTap: () => _open(const DoctorHome(embedded: true))),
                      if (top)
                        ActionTile(
                            title: 'الإعدادات',
                            subtitle: 'الفصل والنسب',
                            icon: Icons.tune_rounded,
                            gradient: p[5],
                            onTap: () => _open(SettingsScreen(onSeed: _seed))),
                    ],
                  ),
                  const SectionTitle('آخر المحاضرات'),
                  if (_loading)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator()))
                  else if (_recent.isEmpty)
                    const EmptyState(
                        icon: Icons.event_busy,
                        text: 'لم تُسجّل أي محاضرة بعد')
                  else
                    ..._recent.take(10).map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SessionTile(s),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seedCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 36),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'قاعدة البيانات فارغة. ارفع بيانات الطلاب والمواد من الملفات المرفقة.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.orange),
            onPressed: _seed,
            child: const Text('تهيئة'),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final LectureSession s;
  const _SessionTile(this.s);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: s.active
                  ? AppColors.grad(AppColors.emerald, const Color(0xFF059669))
                  : AppColors.grad(
                      const Color(0xFF94A3B8), const Color(0xFF64748B)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(s.active ? Icons.sensors : Icons.check_rounded,
                color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.courseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    '${s.doctorName} • ${shiftName(s.shift)} • ${fmtDateTime(s.startTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          if (s.active) const Pill('جارية', color: AppColors.emerald),
        ],
      ),
    );
  }
}
