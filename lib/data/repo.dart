import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart' show rootBundle;

import '../config.dart';
import '../models.dart';

/// واجهة مصدر البيانات. لها تنفيذان:
/// [FirebaseRepo] للتشغيل الحقيقي متعدد الأجهزة، و[LocalRepo] للوضع التجريبي.
abstract class Repo {
  bool get isDemo;

  // ---------- الحساب (البريد الجامعي فقط) ----------
  Future<AppUser?> restoreSession();

  /// الدخول بحساب Google الجامعي. في الوضع التجريبي يُمرَّر البريد مباشرة.
  Future<AppUser> signInWithGoogle({String? demoEmail});

  /// الدخول باسم المستخدم (الرقم المعرفي للطالب) وكلمة المرور.
  /// أول دخول بكلمة المرور الأولية يعيد mustChangePassword = true.
  Future<LoginResult> signInWithPassword(String username, String password);

  /// هل يجب على المستخدم الحالي تغيير كلمة المرور الأولية؟
  Future<bool> needsPasswordChange();
  Future<void> changePassword(String oldPassword, String newPassword);

  /// (للإدارة) إعادة الحساب لكلمة مرور أولية: initPw = null تعني اسم المستخدم.
  Future<void> resetStudentAccount(String studentId, {String? initPw});
  Future<void> resetStaffAccount(String staffId, {String? initPw});
  Future<void> signOut();

  // ---------- تهيئة البيانات ----------
  Future<bool> isSeeded();
  Future<void> seedFromAssets(void Function(String msg) onProgress);

  // ---------- الهيكل ----------
  Future<List<College>> colleges();
  Future<void> saveCollege(College c);
  Future<void> deleteCollege(String id);
  Future<List<Department>> departments();
  Future<void> saveDepartment(Department d);
  Future<void> deleteDepartment(String id);
  Future<List<Course>> courses();
  Future<void> saveCourse(Course c);
  Future<void> deleteCourse(String id);

  // ---------- الطلاب ----------
  Future<List<Student>> students();
  Future<Student?> student(String id);
  Future<Student?> studentByEmail(String email);
  Future<Student?> studentByNfc(String uid);
  Future<void> saveStudent(Student s);
  Future<void> deleteStudent(String id);
  Future<void> setStudentsDept(List<String> ids, String? deptId);

  /// ربط شريحة NFC بطالب (null لإلغاء الربط). يرمي خطأ إن كانت مرتبطة بغيره.
  Future<void> setStudentNfc(String studentId, String? uid);

  // ---------- الكادر ----------
  Future<List<Staff>> staff();
  Future<void> saveStaff(Staff s);
  Future<void> deleteStaff(String id);

  // ---------- الإعدادات ----------
  Future<AppSettings> settings();
  Future<void> saveSettings(AppSettings s);

  // ---------- المحاضرات والحضور ----------
  Future<LectureSession> createSession(LectureSession s);
  Future<void> closeSession(String id);
  Future<void> deleteSession(String id);
  Future<LectureSession?> session(String id);
  Future<List<LectureSession>> sessionsForCourse(String courseId);
  Future<List<LectureSession>> sessionsForDoctor(String doctorId);
  Future<List<LectureSession>> recentSessions({int limit = 50});
  Stream<List<AttendanceRecord>> watchAttendance(String sessionId);
  Future<List<AttendanceRecord>> attendanceForCourse(String courseId);
  Future<List<AttendanceRecord>> attendanceForStudent(String studentId);

  Future<List<LectureSession>> sessionsSince(int ms);
  Future<List<AttendanceRecord>> attendanceSince(int ms);

  // ---------- الحفظ بالجملة (رفع Excel) ----------
  Future<void> saveStudentsBulk(List<Student> list);
  Future<void> saveCoursesBulk(List<Course> list);
  Future<void> saveStaffBulk(List<Staff> list);

  // ---------- الدرجات والدروس ----------
  Future<GradeScheme> scheme(String courseId);
  Future<void> saveScheme(GradeScheme s);
  Future<List<GradeRecord>> gradesForCourse(String courseId);
  Future<List<GradeRecord>> gradesForStudent(String studentId);
  Future<void> saveGradesBulk(List<GradeRecord> list);
  Future<List<Lesson>> lessonsForCourse(String courseId);
  Future<Lesson> saveLesson(Lesson l);
  Future<void> deleteLesson(String id);

  /// يسجل الحضور ويرمي [AppException] إذا كان مسجلاً مسبقاً.
  Future<void> markAttendance(AttendanceRecord r);
  Future<void> removeAttendance(String recordId);
}

/// البيانات الأولية المأخوذة من ملفي Students و Resources.
class SeedData {
  final List<College> colleges;
  final List<Department> departments;
  final List<Course> courses;
  final List<Student> students;
  final List<Staff> staff;
  SeedData(this.colleges, this.departments, this.courses, this.students,
      this.staff);

  static Future<SeedData> load() async {
    final structure = jsonDecode(
        await rootBundle.loadString('assets/data/structure.json')) as Map;
    final courses = jsonDecode(
        await rootBundle.loadString('assets/data/courses.json')) as List;
    final students = jsonDecode(
        await rootBundle.loadString('assets/data/students.json')) as List;
    List staff = const [];
    try {
      staff = jsonDecode(await rootBundle.loadString('assets/data/staff.json'))
          as List;
    } catch (_) {}
    return SeedData(
      (structure['colleges'] as List)
          .map((e) => College.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      (structure['departments'] as List)
          .map((e) => Department.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      courses.map((e) => Course.fromMap(Map<String, dynamic>.from(e))).toList(),
      students
          .map((e) => Student.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      staff.map((e) => Staff.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }
}

/// رمز هوية الطالب المشفّر في QR وفي NFC: ALMAQAL-ST|<الرقم المعرفي>
class StudentCode {
  static String encode(Student s) => '${AppConfig.studentCodePrefix}|${s.id}';

  /// يستخرج الرقم المعرفي أو البريد من نص ممسوح.
  /// يقبل: رمز التطبيق، أو الرقم المعرفي وحده (هوية مطبوعة)، أو البريد الجامعي.
  static ({String? id, String? email}) parse(String raw) {
    final t = raw.trim();
    if (t.startsWith('${AppConfig.studentCodePrefix}|')) {
      final parts = t.split('|');
      if (parts.length >= 2 && parts[1].isNotEmpty) {
        return (id: parts[1], email: null);
      }
      return (id: null, email: null);
    }
    if (t.contains('@')) return (id: null, email: t.toLowerCase());
    if (RegExp(r'^[0-9A-Za-z\-]{4,32}$').hasMatch(t)) {
      return (id: t, email: null);
    }
    return (id: null, email: null);
  }
}

/// حسابات مشتركة بين التنفيذين.
class Stats {
  /// عدد المحاضرات التي تخص الطالب وعدد ما حضره، لكل مادة.
  static StudentCourseStat forStudent(Student s, List<LectureSession> sessions,
      Set<String> attendedSessionIds) {
    final applicable = sessions
        .where((x) =>
            x.appliesTo(s) &&
            (!x.active || attendedSessionIds.contains(x.id)))
        .toList();
    final present =
        applicable.where((x) => attendedSessionIds.contains(x.id)).length;
    return StudentCourseStat(s, applicable.length, present);
  }

  static List<Student> eligibleStudents(
          List<Student> all, Course c, String shift) =>
      all
          .where((s) =>
              s.stage == c.stage &&
              (s.deptId == null || s.deptId == c.deptId) &&
              (shift == 'all' || s.shift == shift))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
}

/// بصمة كلمة المرور (لا تُخزَّن كلمات المرور كنص).
String hashPassword(String username, String password) => sha256
    .convert(utf8.encode('almaqal::${username.toLowerCase()}::$password'))
    .toString();

/// كلمة المرور الأولية المقبولة: ما حدده المدير، وإلا الافتراضية:
/// للطالب = رقمه المعرفي، وللكادر = [AppConfig.defaultStaffPassword].
bool checkInitialPassword(
    {required String username,
    required String? initPw,
    required String password,
    bool isStaff = false}) {
  if (initPw != null && initPw.isNotEmpty) {
    return hashPassword(username, password) == initPw;
  }
  return password == (isStaff ? AppConfig.defaultStaffPassword : username);
}

/// يحوّل ما يكتبه المستخدم إلى (رقم طالب) أو (بريد كادر).
({String? studentId, String? staffEmail}) resolveUsername(String input) {
  final t = input.trim().toLowerCase();
  if (t.isEmpty) return (studentId: null, staffEmail: null);
  if (RegExp(r'^[0-9]+$').hasMatch(t)) return (studentId: t, staffEmail: null);
  if (t.contains('@')) return (studentId: null, staffEmail: t);
  return (studentId: null, staffEmail: '$t@${AppConfig.universityDomain}');
}
