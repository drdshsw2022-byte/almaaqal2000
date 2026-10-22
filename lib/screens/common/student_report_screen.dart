import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/repo.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// بيانات حضور طالب في كل مواده (مشتركة بين لوحة الطالب والمدير).
class StudentCourseSummary {
  final Course course;
  final List<LectureSession> sessions; // المحاضرات التي تخص الطالب
  final Set<String> attended;
  StudentCourseSummary(this.course, this.sessions, this.attended);

  int get total => sessions.length;
  int get present => sessions.where((s) => attended.contains(s.id)).length;
  int get absent => total - present;
  double get absencePercent => total == 0 ? 0 : absent * 100 / total;
  double get attendancePercent => total == 0 ? 100 : present * 100 / total;
}

/// مواد الطالب حسب مرحلته وقسمه والفصل.
Future<List<Course>> coursesForStudent(Student s, {int? term}) async {
  final all = await repo.courses();
  return all
      .where((c) =>
          c.stage == s.stage &&
          (s.deptId == null || c.deptId == s.deptId) &&
          (term == null || c.term == term))
      .toList()
    ..sort((a, b) => a.nameAr.compareTo(b.nameAr));
}

Future<List<StudentCourseSummary>> loadStudentSummary(Student s,
    {int? term}) async {
  final courses = await coursesForStudent(s, term: term);
  final records = await repo.attendanceForStudent(s.id);
  final attended = records.map((r) => r.sessionId).toSet();
  final sessionLists =
      await Future.wait(courses.map((c) => repo.sessionsForCourse(c.id)));
  final out = <StudentCourseSummary>[];
  for (var i = 0; i < courses.length; i++) {
    // المحاضرة الجارية لا تُحسب غياباً حتى تنتهي
    final applicable = sessionLists[i]
        .where((x) =>
            x.appliesTo(s) && (!x.active || attended.contains(x.id)))
        .toList();
    out.add(StudentCourseSummary(courses[i], applicable, attended));
  }
  // إخفاء المواد التي ليس لها محاضرات في حال عدم تعيين القسم (لتقليل التشويش)
  if (s.deptId == null) {
    final withSessions = out.where((x) => x.total > 0).toList();
    if (withSessions.isNotEmpty) return withSessions;
  }
  return out;
}

class StudentReportScreen extends StatefulWidget {
  final Student student;
  const StudentReportScreen({super.key, required this.student});

  @override
  State<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends State<StudentReportScreen> {
  List<StudentCourseSummary> _data = [];
  bool _loading = true;
  int? _term;

  @override
  void initState() {
    super.initState();
    _term = AppState.settings.currentTerm;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await loadStudentSummary(widget.student, term: _term);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    return Scaffold(
      appBar: gradientAppBar('سجل حضور الطالب'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  gradient: AppColors.mainGradient,
                  borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      '${s.id} • ${stageName(s.stage)} • ${shiftName(s.shift)}',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('الفصل الأول')),
                ButtonSegment(value: 2, label: Text('الفصل الثاني')),
                ButtonSegment(value: 0, label: Text('الكل')),
              ],
              selected: {_term ?? 0},
              onSelectionChanged: (v) {
                _term = v.first == 0 ? null : v.first;
                _load();
              },
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()))
            else if (_data.isEmpty)
              const EmptyState(icon: Icons.menu_book, text: 'لا توجد مواد')
            else
              ..._data.map((d) => CourseAttendanceCard(
                    summary: d,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => StudentCourseSessionsScreen(
                                summary: d, student: s))),
                  )),
          ],
        ),
      ),
    );
  }
}

class CourseAttendanceCard extends StatelessWidget {
  final StudentCourseSummary summary;
  final VoidCallback? onTap;
  const CourseAttendanceCard({super.key, required this.summary, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = summary;
    final st = absenceStatus(d.absencePercent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleProgress(
                    percent: d.attendancePercent, color: st.color, size: 58),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.course.nameAr,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(d.course.code,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: d.total == 0 ? 0 : d.present / d.total,
                          minHeight: 7,
                          backgroundColor: st.color.withOpacity(0.12),
                          valueColor: AlwaysStoppedAnimation(st.color),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          'حضور ${d.present} • غياب ${d.absent} من ${d.total} محاضرة',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Pill(st.label, color: st.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StudentCourseSessionsScreen extends StatelessWidget {
  final StudentCourseSummary summary;
  final Student student;
  const StudentCourseSessionsScreen(
      {super.key, required this.summary, required this.student});

  @override
  Widget build(BuildContext context) {
    final list = summary.sessions;
    return Scaffold(
      appBar: gradientAppBar(summary.course.nameAr),
      body: list.isEmpty
          ? const EmptyState(
              icon: Icons.event_available, text: 'لم تُسجّل محاضرات بعد')
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                final ok = summary.attended.contains(s.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: (ok ? AppColors.emerald : AppColors.rose)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(ok ? Icons.check_rounded : Icons.close_rounded,
                          color: ok ? AppColors.emerald : AppColors.rose),
                    ),
                    title: Text(
                        s.title.isEmpty ? 'محاضرة ${list.length - i}' : s.title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${dayName(s.startTime)} ${fmtDateTime(s.startTime)}\n${s.doctorName}',
                        style: const TextStyle(fontSize: 12)),
                    isThreeLine: true,
                    trailing: Pill(ok ? 'حاضر' : (s.active ? 'جارية' : 'غائب'),
                        color: ok
                            ? AppColors.emerald
                            : (s.active ? AppColors.orange : AppColors.rose)),
                  ),
                );
              },
            ),
    );
  }
}
