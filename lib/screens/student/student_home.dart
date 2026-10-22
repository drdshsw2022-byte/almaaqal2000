import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../services/nfc_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../common/lessons_screen.dart';
import '../common/profile_sheet.dart';
import '../common/student_report_screen.dart';
import 'id_card_screen.dart';

/// لوحة الطالب: الرئيسية • الغياب • الدرجات • الدروس.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _CourseGrades {
  final Course course;
  final GradeScheme scheme;
  final GradeRecord? record;
  _CourseGrades(this.course, this.scheme, this.record);
}

class _StudentHomeState extends State<StudentHome> {
  int _tab = 0;
  bool _loading = true;
  List<StudentCourseSummary> _absence = [];
  List<_CourseGrades> _grades = [];
  List<(Course, Lesson)> _lessons = [];
  String? _deptName;

  Student get _me => AppState.user.value!.student!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fresh = await repo.student(_me.id);
      if (fresh != null) AppState.user.value = AppUser.student(fresh);
      final me = _me;
      // تجهيز هوية NFC أولاً كي تعمل حتى لو تعذّر تحميل بقية البيانات
      try {
        await NfcService.setStudentPayload(StudentCode.encode(me));
      } catch (_) {}
      final depts = await repo.departments();
      _deptName =
          depts.where((d) => d.id == me.deptId).map((d) => d.name).firstOrNull;
      final term = AppState.settings.currentTerm;
      final courses = await coursesForStudent(me, term: term);
      final r = await Future.wait([
        loadStudentSummary(me, term: term),
        repo.gradesForStudent(me.id),
        Future.wait(courses.map((c) => repo.scheme(c.id))),
        Future.wait(courses.map((c) => repo.lessonsForCourse(c.id))),
      ]);
      _absence = r[0] as List<StudentCourseSummary>;
      final recs = {
        for (final g in r[1] as List<GradeRecord>) g.courseId: g
      };
      final schemes = r[2] as List<GradeScheme>;
      final lessons = r[3] as List<List<Lesson>>;
      _grades = [
        for (var i = 0; i < courses.length; i++)
          if (me.deptId != null || recs.containsKey(courses[i].id))
            _CourseGrades(courses[i], schemes[i], recs[courses[i].id])
      ];
      // نتائج رفعها الدكتور لمواد خارج قائمة الفصل الحالي تظهر أيضاً
      final shownIds = _grades.map((g) => g.course.id).toSet();
      final extraIds =
          recs.keys.where((id) => !shownIds.contains(id)).toList();
      if (extraIds.isNotEmpty) {
        final all = {for (final c in await repo.courses()) c.id: c};
        for (final id in extraIds) {
          final c = all[id];
          if (c == null) continue;
          _grades.add(_CourseGrades(c, await repo.scheme(id), recs[id]));
        }
      }
      _lessons = [
        for (var i = 0; i < courses.length; i++)
          for (final l in lessons[i]) (courses[i], l)
      ]..sort((a, b) => b.$2.date.compareTo(a.$2.date));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openCard() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => IdCardScreen(student: _me)));

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final pages = [_homeTab(me), _absenceTab(me), _gradesTab(), _lessonsTab()];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              title: me.name,
              subtitle:
                  'الرقم الجامعي: ${me.id} • ${stageName(me.stage)} • ${shiftName(me.shift)}${_deptName != null ? '\n$_deptName' : ''}',
              roleIcon: Icons.school_rounded,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()))
                  : pages[_tab],
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'الرئيسية'),
          NavigationDestination(
              icon: Icon(Icons.event_busy_outlined),
              selectedIcon: Icon(Icons.event_busy),
              label: 'الغياب'),
          NavigationDestination(
              icon: Icon(Icons.grading_outlined),
              selectedIcon: Icon(Icons.grading),
              label: 'الدرجات'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'الدروس'),
        ],
      ),
    );
  }

  // ---------------- الرئيسية ----------------
  Widget _homeTab(Student me) {
    final total = _absence.fold<int>(0, (a, d) => a + d.total);
    final present = _absence.fold<int>(0, (a, d) => a + d.present);
    final rate = total == 0 ? 100.0 : present * 100 / total;
    final warnings = _absence
        .where((d) => absenceStatus(d.absencePercent).color != AppColors.emerald)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _openCard,
          child: StudentIdCard(student: me, deptName: _deptName, compact: true),
        ),
        TextButton.icon(
          onPressed: _openCard,
          icon: const Icon(Icons.qr_code_2),
          label: const Text('عرض الهوية كاملة للمسح'),
        ),
        Row(
          children: [
            Expanded(
                child: StatCard(
                    label: 'نسبة الحضور',
                    value: '${rate.round()}%',
                    icon: Icons.trending_up_rounded,
                    gradient: AppColors.tilePalette[2])),
            const SizedBox(width: 10),
            Expanded(
                child: StatCard(
                    label: 'محاضرات حضرتها',
                    value: '$present/$total',
                    icon: Icons.event_available_rounded,
                    gradient: AppColors.tilePalette[1])),
          ],
        ),
        if (warnings > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.orange.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'لديك $warnings مادة تجاوزت نسبة الغياب المسموح بها للإنذار. انتبه لحضورك!',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
        if (_lessons.isNotEmpty) ...[
          const SectionTitle('أحدث الدروس'),
          ..._lessons.take(3).map((x) => LessonTile(
              lesson: x.$2, courseName: x.$1.nameAr)),
        ],
      ],
    );
  }

  // ---------------- الغياب ----------------
  Widget _absenceTab(Student me) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('الحضور والغياب • ${termName(AppState.settings.currentTerm)}',
            trailing: TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StudentReportScreen(student: me))),
              child: const Text('السجل الكامل'),
            )),
        if (_absence.isEmpty)
          const EmptyState(
              icon: Icons.event_note, text: 'لا توجد محاضرات مسجلة لك بعد')
        else
          ..._absence.map((d) => CourseAttendanceCard(
                summary: d,
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            StudentCourseSessionsScreen(summary: d, student: me))),
              )),
      ],
    );
  }

  // ---------------- الدرجات ----------------
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _gradesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('الدرجات • ${termName(AppState.settings.currentTerm)}'),
        if (_grades.isEmpty)
          const EmptyState(icon: Icons.grading, text: 'لا توجد درجات منشورة بعد')
        else ...[
          _fullRecord(),
          const SectionTitle('التفاصيل حسب المادة'),
          ..._grades.map(_gradeCard),
        ],
      ],
    );
  }

  /// سجل النتائج التفصيلي: صف لكل مادة وعمود لكل مكوّن (كسجل درجات الجامعة).
  Widget _fullRecord() {
    const head = TextStyle(
        fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.night);
    DataCell cell(String t, {Color? color, bool bold = false}) => DataCell(
          Center(
            child: Text(t,
                style: TextStyle(
                    fontSize: 12.5,
                    color: color,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ),
        );
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              gradient: AppColors.mainGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: const Row(
              children: [
                Icon(Icons.table_chart_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('سجل النتائج التفصيلي',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 52,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              columnSpacing: 14,
              horizontalMargin: 12,
              headingRowColor:
                  WidgetStateProperty.all(AppColors.royal.withOpacity(0.06)),
              columns: [
                const DataColumn(label: Text('المادة', style: head)),
                ...gradeComponents.map((k) => DataColumn(
                    label: Text(componentName(k).replaceFirst(' ', '\n'),
                        textAlign: TextAlign.center, style: head))),
                const DataColumn(
                    label: Text('الدرجة\nالنهائية',
                        textAlign: TextAlign.center, style: head)),
                const DataColumn(label: Text('التقدير', style: head)),
              ],
              rows: _grades.map((g) {
                final sch = g.scheme;
                final pub =
                    sch.active.where((k) => sch.published.contains(k)).toList();
                final complete =
                    pub.isNotEmpty && pub.length == sch.active.length;
                final total = g.record?.totalOf(pub) ?? 0;
                final letter = gradeLetter(total);
                return DataRow(cells: [
                  DataCell(SizedBox(
                    width: 140,
                    child: Text(g.course.nameAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  )),
                  ...gradeComponents.map((k) {
                    if ((sch.max[k] ?? 0) <= 0) return cell('—', color: AppColors.muted);
                    if (!sch.published.contains(k)) {
                      return cell('…', color: AppColors.muted);
                    }
                    final v = g.record?.marks[k];
                    return cell(v == null ? '—' : _fmt(v));
                  }),
                  cell(pub.isEmpty ? '—' : _fmt(total), bold: true),
                  cell(
                      complete ? letter.label : (pub.isEmpty ? 'لم تُنشر' : 'جزئي'),
                      color: complete
                          ? (letter.pass ? AppColors.emerald : AppColors.rose)
                          : AppColors.muted,
                      bold: true),
                ]);
              }).toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Text(
              '«…» درجة لم ينشرها التدريسي بعد • «—» لا يوجد هذا المكوّن في المادة أو لم تُرصد',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeCard(_CourseGrades g) {
    final sch = g.scheme;
    final pub = sch.active.where((k) => sch.published.contains(k)).toList();
    final total = g.record?.totalOf(pub) ?? 0;
    final maxPub = pub.fold<double>(0, (a, k) => a + (sch.max[k] ?? 0));
    final complete = pub.length == sch.active.length && pub.isNotEmpty;
    final letter = gradeLetter(total);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: AppColors.tilePalette[g.course.semester % 8],
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.course.nameAr,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      Text(g.course.code,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(pub.isEmpty ? '—' : _fmt(total),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    Text(
                        pub.isEmpty
                            ? 'لم تُنشر'
                            : (complete ? letter.label : 'من ${_fmt(maxPub)}'),
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: sch.active.map((k) {
                final shown = sch.published.contains(k);
                final v = g.record?.marks[k];
                final mx = sch.max[k] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 110,
                          child: Text(componentName(k),
                              style: const TextStyle(fontSize: 13))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (!shown || v == null || mx == 0)
                                ? 0
                                : (v / mx).clamp(0.0, 1.0).toDouble(),
                            minHeight: 8,
                            backgroundColor: AppColors.bg,
                            valueColor:
                                const AlwaysStoppedAnimation(AppColors.royal),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 70,
                        child: Text(
                            !shown
                                ? 'غير منشورة'
                                : '${v == null ? '—' : _fmt(v)} / ${_fmt(mx)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: shown ? AppColors.text : AppColors.muted)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- الدروس ----------------
  Widget _lessonsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('الدروس والمحاضرات (${_lessons.length})'),
        if (_lessons.isEmpty)
          const EmptyState(
              icon: Icons.menu_book, text: 'لم يضف التدريسيون دروساً بعد')
        else
          ..._lessons
              .map((x) => LessonTile(lesson: x.$2, courseName: x.$1.nameAr)),
      ],
    );
  }
}
