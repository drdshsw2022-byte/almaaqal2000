import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../models.dart';
import 'repo.dart';

/// التنفيذ الحقيقي على Firebase (Auth + Firestore).
///
/// الدخول بحساب Google الجامعي (@almaaqal.edu.iq) فقط.
/// الكادر: مستند staff/<البريد>. الطالب: مستند students/<الرقم المعرفي> بحقل email.
class FirebaseRepo implements Repo {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _google = GoogleSignIn(
    scopes: const ['email'],
    hostedDomain: AppConfig.universityDomain,
    serverClientId: AppConfig.googleWebClientId.isEmpty
        ? null
        : AppConfig.googleWebClientId,
  );
  // للمدير العام من خارج نطاق الجامعة
  final _googleAny = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: AppConfig.googleWebClientId.isEmpty
        ? null
        : AppConfig.googleWebClientId,
  );

  List<Student>? _studentsCache;
  List<Course>? _coursesCache;

  @override
  bool get isDemo => false;

  CollectionReference<Map<String, dynamic>> get _students =>
      _db.collection('students');
  CollectionReference<Map<String, dynamic>> get _staff =>
      _db.collection('staff');
  CollectionReference<Map<String, dynamic>> get _courses =>
      _db.collection('courses');
  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sessions');
  CollectionReference<Map<String, dynamic>> get _attendance =>
      _db.collection('attendance');

  String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'تعذّر الاتصال بالإنترنت';
      case 'too-many-requests':
        return 'محاولات كثيرة، حاول لاحقاً';
      case 'user-disabled':
        return 'هذا الحساب معطّل';
      default:
        return e.message ?? 'خطأ في المصادقة (${e.code})';
    }
  }

  Future<AppUser?> _profileByEmail(String email) async {
    email = email.toLowerCase();
    final st = await _staff.doc(email).get();
    if (st.exists) return AppUser.staff(Staff.fromMap(st.data()!));
    final s = await _students.where('email', isEqualTo: email).limit(1).get();
    if (s.docs.isNotEmpty) {
      return AppUser.student(Student.fromMap(s.docs.first.data()));
    }
    // بريد بصيغة <الرقم المعرفي>@النطاق لطالب لم يُسجَّل بريده بعد
    if (AppConfig.isUniversityEmail(email)) {
      final byId = await _students.doc(email.split('@').first).get();
      if (byId.exists) {
        final stu = Student.fromMap(byId.data()!);
        if (stu.email == null) return AppUser.student(stu);
      }
    }
    if (AppConfig.superAdminEmails.contains(email)) {
      // تهيئة المدير العام تلقائياً عند أول دخول
      final admin = Staff(id: email, name: 'مدير النظام', role: 'admin');
      await _staff.doc(admin.id).set(admin.toMap());
      return AppUser.staff(admin);
    }
    return null;
  }

  // ---------------- الحساب ----------------
  @override
  Future<AppUser?> restoreSession() async {
    final u = _auth.currentUser;
    if (u?.email == null) return null;
    try {
      return await _profileForAuthEmail(u!.email!);
    } catch (_) {
      return null;
    }
  }

  // ---------------- الدخول بكلمة المرور ----------------
  static String _studentAuth(String id) => '$id@${AppConfig.studentAuthDomain}';
  static String _staffAuth(String uniEmail) =>
      '${uniEmail.split('@').first}@${AppConfig.staffAuthDomain}';
  static String get _bootstrapEmail =>
      '${AppConfig.bootstrapAdminUsername}@${AppConfig.universityDomain}';

  /// يحمّل الملف حسب بريد المصادقة (داخلي أو بريد Google).
  Future<AppUser?> _profileForAuthEmail(String authEmail) async {
    final e = authEmail.toLowerCase();
    final local = e.split('@').first;
    if (e.endsWith('@${AppConfig.studentAuthDomain}')) {
      final d = await _students.doc(local).get();
      return d.exists ? AppUser.student(Student.fromMap(d.data()!)) : null;
    }
    if (e.endsWith('@${AppConfig.staffAuthDomain}')) {
      final d = await _staff.doc(await _staffDocFor(local)).get();
      return d.exists ? AppUser.staff(Staff.fromMap(d.data()!)) : null;
    }
    return _profileByEmail(e);
  }

  /// معرّف مستند الكادر لحساب كلمة مرور داخلي: عبر فهرس usernames أو بريد الجامعة.
  Future<String> _staffDocFor(String local) async {
    try {
      final a = await _db.collection('usernames').doc(local).get();
      final e = a.data()?['email'];
      if (e is String && e.isNotEmpty) return e.toLowerCase();
    } catch (_) {}
    return '$local@${AppConfig.universityDomain}';
  }

  bool _isWrongCreds(FirebaseAuthException e) => const [
        'user-not-found',
        'wrong-password',
        'invalid-credential',
        'invalid-login-credentials',
        'INVALID_LOGIN_CREDENTIALS',
      ].contains(e.code);

  Future<void> _abort(String msg) async {
    try {
      await _auth.currentUser?.delete();
    } catch (_) {}
    await _auth.signOut();
    throw AppException(msg);
  }

  @override
  Future<LoginResult> signInWithPassword(String username, String password) async {
    var r = resolveUsername(username);
    if (r.studentId == null && r.staffEmail == null) {
      throw AppException('أدخل اسم المستخدم');
    }
    // اسم مستخدم مختار (مثل doc01) ← بريد الدكتور
    final typed = username.trim().toLowerCase();
    String? aliasUsed;
    if (r.staffEmail != null && !typed.contains('@')) {
      try {
        final a = await _db.collection('usernames').doc(typed).get();
        final e = a.data()?['email'];
        if (e is String && e.isNotEmpty) {
          r = (studentId: null, staffEmail: e.toLowerCase());
          aliasUsed = typed;
        }
      } catch (_) {}
    }
    if (r.staffEmail != null &&
        aliasUsed == null &&
        !AppConfig.isUniversityEmail(r.staffEmail!)) {
      throw AppException('ادخل باسم المستخدم المخصص لك (مثل doc01)');
    }
    final authEmail = r.studentId != null
        ? _studentAuth(r.studentId!)
        : (aliasUsed != null
            ? '$aliasUsed@${AppConfig.staffAuthDomain}'
            : _staffAuth(r.staffEmail!));
    final uname = r.studentId ?? r.staffEmail!.split('@').first;
    try {
      await _auth.signInWithEmailAndPassword(email: authEmail, password: password);
      final p = await _profileForAuthEmail(authEmail);
      if (p == null) {
        await _auth.signOut();
        throw AppException('الحساب غير موجود في قاعدة البيانات');
      }
      final activated = p.student?.activated ?? p.staff!.activated;
      return LoginResult(p, mustChangePassword: !activated);
    } on FirebaseAuthException catch (e) {
      if (!_isWrongCreds(e)) throw AppException(_authError(e));
    }
    // أول دخول: إنشاء الحساب بكلمة المرور الأولية ثم التحقق منها
    try {
      await _auth.createUserWithEmailAndPassword(email: authEmail, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw AppException('كلمة المرور غير صحيحة');
      }
      if (e.code == 'weak-password') {
        throw AppException('كلمة المرور غير صحيحة');
      }
      throw AppException(_authError(e));
    }
    final isBoot = r.staffEmail == _bootstrapEmail;
    var p = await _profileForAuthEmail(authEmail);
    if (p == null && isBoot && password == AppConfig.bootstrapAdminPassword) {
      final admin = Staff(id: _bootstrapEmail, name: 'مدير النظام', role: 'admin');
      await _staff.doc(admin.id).set(admin.toMap());
      p = AppUser.staff(admin);
    }
    if (p == null) {
      await _abort('اسم المستخدم غير موجود في قاعدة بيانات الجامعة');
    }
    final user = p!;
    if (user.student?.activated ?? user.staff!.activated) {
      await _abort('هذا الحساب مفعّل مسبقاً. راجع الإدارة لإعادة تعيين كلمة المرور');
    }
    final ok = isBoot
        ? password == AppConfig.bootstrapAdminPassword
        : checkInitialPassword(
            username: uname,
            initPw: user.student?.initPw ?? user.staff?.initPw,
            password: password,
            isStaff: user.staff != null);
    if (!ok) await _abort('كلمة المرور غير صحيحة');
    return LoginResult(user, mustChangePassword: true);
  }

  @override
  Future<bool> needsPasswordChange() async {
    final u = _auth.currentUser;
    final e = u?.email;
    if (e == null) return false;
    final synthetic = e.endsWith('@${AppConfig.studentAuthDomain}') ||
        e.endsWith('@${AppConfig.staffAuthDomain}');
    if (!synthetic) return false;
    final p = await _profileForAuthEmail(e);
    return p != null && !(p.student?.activated ?? p.staff!.activated);
  }

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final u = _auth.currentUser;
    final e = u?.email;
    if (u == null || e == null) throw AppException('لم يتم تسجيل الدخول');
    if (!e.endsWith('@${AppConfig.studentAuthDomain}') &&
        !e.endsWith('@${AppConfig.staffAuthDomain}')) {
      throw AppException('دخلت بحساب Google ولا تحتاج كلمة مرور');
    }
    try {
      await u.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: e, password: oldPassword));
      await u.updatePassword(newPassword);
    } on FirebaseAuthException catch (x) {
      if (_isWrongCreds(x)) throw AppException('كلمة المرور الحالية غير صحيحة');
      if (x.code == 'weak-password') {
        throw AppException('كلمة المرور ضعيفة (6 أحرف على الأقل)');
      }
      throw AppException(_authError(x));
    }
    final local = e.split('@').first;
    if (e.endsWith('@${AppConfig.studentAuthDomain}')) {
      await _students.doc(local).update({'activated': true});
    } else {
      await _staff.doc(await _staffDocFor(local)).update({'activated': true});
    }
  }

  @override
  Future<void> resetStudentAccount(String studentId, {String? initPw}) async {
    await _students.doc(studentId).update({
      'activated': false,
      'initPw': initPw == null ? null : hashPassword(studentId, initPw),
    });
    _studentsCache = null;
  }

  @override
  Future<void> resetStaffAccount(String staffId, {String? initPw}) async {
    await _staff.doc(staffId).update({
      'activated': false,
      'initPw': initPw == null
          ? null
          : hashPassword(staffId.split('@').first, initPw),
    });
  }

  @override
  Future<AppUser> signInWithGoogle({String? demoEmail}) async {
    // demoEmail هنا = "superadmin" لفتح نافذة اختيار أي حساب للمدير العام
    final g = demoEmail == 'superadmin' ? _googleAny : _google;
    final acc = await g.signIn();
    if (acc == null) throw AppException('تم إلغاء تسجيل الدخول');
    final email = acc.email.toLowerCase();
    if (!AppConfig.isAllowedEmail(email)) {
      await g.signOut();
      throw AppException(
          'يُقبل البريد الجامعي الرسمي فقط (@${AppConfig.universityDomain})');
    }
    final ga = await acc.authentication;
    final credential = GoogleAuthProvider.credential(
        idToken: ga.idToken, accessToken: ga.accessToken);
    try {
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      await g.signOut();
      throw AppException(_authError(e));
    }
    final p = await _profileByEmail(email);
    if (p == null) {
      await _auth.signOut();
      await g.signOut();
      throw NotRegisteredException(email);
    }
    return p;
  }

  @override
  Future<void> signOut() async {
    _studentsCache = null;
    _coursesCache = null;
    for (final g in [_google, _googleAny]) {
      try {
        await g.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  // ---------------- تهيئة ----------------
  @override
  Future<bool> isSeeded() async {
    final d = await _db.collection('meta').doc('seed').get();
    return d.exists;
  }

  Future<void> _batchWrite(
      String collection,
      List<Map<String, dynamic>> items,
      void Function(String) onProgress,
      String label) async {
    const chunk = 400;
    for (var i = 0; i < items.length; i += chunk) {
      final b = _db.batch();
      for (final m in items.skip(i).take(chunk)) {
        b.set(_db.collection(collection).doc('${m['id']}'), m,
            SetOptions(merge: true));
      }
      await b.commit();
      final done = (i + chunk).clamp(0, items.length);
      onProgress('$label: $done / ${items.length}');
    }
  }

  @override
  Future<void> seedFromAssets(void Function(String msg) onProgress) async {
    onProgress('جاري قراءة الملفات...');
    final d = await SeedData.load();
    await _batchWrite('colleges', d.colleges.map((e) => e.toMap()).toList(),
        onProgress, 'الكليات');
    await _batchWrite('departments',
        d.departments.map((e) => e.toMap()).toList(), onProgress, 'الأقسام');
    await _batchWrite(
        'courses', d.courses.map((e) => e.toMap()).toList(), onProgress, 'المواد');
    // للطلاب: لا نمسح ربط NFC ولا ما عدّله المدير إن كان الملف لا يحويه
    await _batchWrite(
        'students',
        d.students
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'stage': s.stage,
                  'shift': s.shift,
                  if (s.deptId != null) 'deptId': s.deptId,
                  if (s.email != null) 'email': s.email,
                })
            .toList(),
        onProgress,
        'الطلاب');
    if (d.staff.isNotEmpty) {
      await _batchWrite(
          'staff',
          d.staff
              .map((x) => {
                    'id': x.id,
                    'email': x.id,
                    'name': x.name,
                    'role': x.role,
                    'alias': x.alias,
                    'initPw': x.initPw,
                  })
              .toList(),
          onProgress,
          'الكادر');
      await _batchWrite(
          'usernames',
          d.staff
              .where((x) => x.alias != null)
              .map((x) => {'id': x.alias, 'email': x.id})
              .toList(),
          onProgress,
          'أسماء المستخدمين');
    }
    await _db
        .collection('settings')
        .doc('app')
        .set(const AppSettings().toMap(), SetOptions(merge: true));
    await _db.collection('meta').doc('seed').set({
      'at': DateTime.now().millisecondsSinceEpoch,
      'students': d.students.length,
      'courses': d.courses.length,
    });
    _studentsCache = null;
    _coursesCache = null;
    onProgress('تمت التهيئة بنجاح');
  }

  // ---------------- الهيكل ----------------
  @override
  Future<List<College>> colleges() async {
    final q = await _db.collection('colleges').get();
    return q.docs.map((d) => College.fromMap(d.data())).toList();
  }

  @override
  Future<void> saveCollege(College c) =>
      _db.collection('colleges').doc(c.id).set(c.toMap());

  @override
  Future<void> deleteCollege(String id) =>
      _db.collection('colleges').doc(id).delete();

  @override
  Future<List<Department>> departments() async {
    final q = await _db.collection('departments').get();
    return q.docs.map((d) => Department.fromMap(d.data())).toList();
  }

  @override
  Future<void> saveDepartment(Department d) =>
      _db.collection('departments').doc(d.id).set(d.toMap());

  @override
  Future<void> deleteDepartment(String id) =>
      _db.collection('departments').doc(id).delete();

  @override
  Future<List<Course>> courses() async {
    final cached = _coursesCache;
    if (cached != null) return cached;
    final q = await _courses.get();
    return _coursesCache = q.docs.map((d) => Course.fromMap(d.data())).toList();
  }

  @override
  Future<void> saveCourse(Course c) async {
    await _courses.doc(c.id).set(c.toMap());
    _coursesCache = null;
  }

  @override
  Future<void> deleteCourse(String id) async {
    await _courses.doc(id).delete();
    _coursesCache = null;
  }

  // ---------------- الطلاب ----------------
  @override
  Future<List<Student>> students() async {
    final cached = _studentsCache;
    if (cached != null) return cached;
    final q = await _students.get();
    return _studentsCache =
        q.docs.map((d) => Student.fromMap(d.data())).toList();
  }

  @override
  Future<Student?> student(String id) async {
    final d = await _students.doc(id).get();
    return d.exists ? Student.fromMap(d.data()!) : null;
  }

  @override
  Future<Student?> studentByEmail(String email) async =>
      (await _profileByEmail(email))?.student;

  @override
  Future<Student?> studentByNfc(String uid) async {
    final q = await _students
        .where('nfcUid', isEqualTo: uid.toUpperCase())
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : Student.fromMap(q.docs.first.data());
  }

  @override
  Future<void> saveStudent(Student s) async {
    await _students.doc(s.id).set(s.toMap());
    _studentsCache = null;
  }

  @override
  Future<void> deleteStudent(String id) async {
    await _students.doc(id).delete();
    _studentsCache = null;
  }

  @override
  Future<void> setStudentsDept(List<String> ids, String? deptId) async {
    const chunk = 400;
    for (var i = 0; i < ids.length; i += chunk) {
      final b = _db.batch();
      for (final id in ids.skip(i).take(chunk)) {
        b.update(_students.doc(id), {'deptId': deptId});
      }
      await b.commit();
    }
    _studentsCache = null;
  }

  @override
  Future<void> setStudentNfc(String studentId, String? uid) async {
    if (uid != null) {
      final other = await studentByNfc(uid);
      if (other != null && other.id != studentId) {
        throw AppException('هذه البطاقة مرتبطة بالطالب ${other.name}');
      }
    }
    await _students
        .doc(studentId)
        .update({'nfcUid': uid?.toUpperCase()});
    _studentsCache = null;
  }

  // ---------------- الكادر ----------------
  @override
  Future<List<Staff>> staff() async {
    final q = await _staff.get();
    return q.docs.map((d) => Staff.fromMap(d.data())).toList();
  }

  @override
  Future<void> saveStaff(Staff s) async {
    await _staff.doc(s.id).set(s.toMap());
    if (s.alias != null) {
      try {
        await _db.collection('usernames').doc(s.alias).set({'email': s.id});
      } catch (_) {
        // فهرس أسماء المستخدمين تكتبه الإدارة العليا فقط
      }
    }
  }

  @override
  Future<void> deleteStaff(String id) => _staff.doc(id).delete();

  // ---------------- الإعدادات ----------------
  @override
  Future<AppSettings> settings() async {
    final d = await _db.collection('settings').doc('app').get();
    return AppSettings.fromMap(d.data());
  }

  @override
  Future<void> saveSettings(AppSettings s) =>
      _db.collection('settings').doc('app').set(s.toMap());

  // ---------------- المحاضرات ----------------
  @override
  Future<LectureSession> createSession(LectureSession s) async {
    final ref = _sessions.doc();
    final created = s.copyWith(id: ref.id);
    await ref.set(created.toMap());
    return created;
  }

  @override
  Future<void> closeSession(String id) => _sessions.doc(id).update(
      {'active': false, 'endedAt': DateTime.now().millisecondsSinceEpoch});

  @override
  Future<void> deleteSession(String id) async {
    final q = await _attendance.where('sessionId', isEqualTo: id).get();
    final b = _db.batch();
    for (final d in q.docs) {
      b.delete(d.reference);
    }
    b.delete(_sessions.doc(id));
    await b.commit();
  }

  @override
  Future<LectureSession?> session(String id) async {
    final d = await _sessions.doc(id).get();
    return d.exists ? LectureSession.fromMap(d.data()!) : null;
  }

  List<LectureSession> _sorted(QuerySnapshot<Map<String, dynamic>> q) =>
      q.docs.map((d) => LectureSession.fromMap(d.data())).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  @override
  Future<List<LectureSession>> sessionsForCourse(String courseId) async =>
      _sorted(await _sessions.where('courseId', isEqualTo: courseId).get());

  @override
  Future<List<LectureSession>> sessionsForDoctor(String doctorId) async =>
      _sorted(await _sessions.where('doctorId', isEqualTo: doctorId).get());

  @override
  Future<List<LectureSession>> recentSessions({int limit = 50}) async =>
      _sorted(await _sessions
          .orderBy('startedAt', descending: true)
          .limit(limit)
          .get());

  @override
  Stream<List<AttendanceRecord>> watchAttendance(String sessionId) =>
      _attendance.where('sessionId', isEqualTo: sessionId).snapshots().map(
          (q) => q.docs.map((d) => AttendanceRecord.fromMap(d.data())).toList()
            ..sort((a, b) => b.time.compareTo(a.time)));

  @override
  Future<List<AttendanceRecord>> attendanceForCourse(String courseId) async {
    final q = await _attendance.where('courseId', isEqualTo: courseId).get();
    return q.docs.map((d) => AttendanceRecord.fromMap(d.data())).toList();
  }

  @override
  Future<List<AttendanceRecord>> attendanceForStudent(String studentId) async {
    final q = await _attendance.where('studentId', isEqualTo: studentId).get();
    return q.docs.map((d) => AttendanceRecord.fromMap(d.data())).toList();
  }

  @override
  Future<List<LectureSession>> sessionsSince(int ms) async =>
      _sorted(await _sessions.where('startedAt', isGreaterThanOrEqualTo: ms).get());

  @override
  Future<List<AttendanceRecord>> attendanceSince(int ms) async {
    final q = await _attendance.where('time', isGreaterThanOrEqualTo: ms).get();
    return q.docs.map((d) => AttendanceRecord.fromMap(d.data())).toList();
  }

  Future<void> _bulk(String col, List<Map<String, dynamic>> items) async {
    const chunk = 400;
    for (var i = 0; i < items.length; i += chunk) {
      final b = _db.batch();
      for (final m in items.skip(i).take(chunk)) {
        b.set(_db.collection(col).doc('${m['id']}'), m, SetOptions(merge: true));
      }
      await b.commit();
    }
  }

  @override
  Future<void> saveStudentsBulk(List<Student> list) async {
    await _bulk('students', list.map((s) => s.toMap()).toList());
    _studentsCache = null;
  }

  @override
  Future<void> saveCoursesBulk(List<Course> list) async {
    await _bulk('courses', list.map((c) => c.toMap()).toList());
    _coursesCache = null;
  }

  @override
  Future<void> saveStaffBulk(List<Staff> list) async {
    await _bulk('staff', list.map((s) => s.toMap()).toList());
    final aliases = list
        .where((s) => s.alias != null)
        .map((s) => {'id': s.alias, 'email': s.id})
        .toList();
    if (aliases.isNotEmpty) await _bulk('usernames', aliases);
  }

  // ---------------- الدرجات والدروس ----------------
  @override
  Future<GradeScheme> scheme(String courseId) async {
    final d = await _db.collection('schemes').doc(_safe(courseId)).get();
    return GradeScheme.fromMap(courseId, d.data());
  }

  @override
  Future<void> saveScheme(GradeScheme s) =>
      _db.collection('schemes').doc(_safe(s.courseId)).set(s.toMap());

  @override
  Future<List<GradeRecord>> gradesForCourse(String courseId) async {
    final q = await _db
        .collection('grades')
        .where('courseId', isEqualTo: courseId)
        .get();
    return q.docs.map((d) => GradeRecord.fromMap(d.data())).toList();
  }

  @override
  Future<List<GradeRecord>> gradesForStudent(String studentId) async {
    final q = await _db
        .collection('grades')
        .where('studentId', isEqualTo: studentId)
        .get();
    return q.docs.map((d) => GradeRecord.fromMap(d.data())).toList();
  }

  @override
  Future<void> saveGradesBulk(List<GradeRecord> list) async {
    const chunk = 400;
    for (var i = 0; i < list.length; i += chunk) {
      final b = _db.batch();
      for (final g in list.skip(i).take(chunk)) {
        b.set(_db.collection('grades').doc(_safe(g.id)), g.toMap());
      }
      await b.commit();
    }
  }

  @override
  Future<List<Lesson>> lessonsForCourse(String courseId) async {
    final q = await _db
        .collection('lessons')
        .where('courseId', isEqualTo: courseId)
        .get();
    return q.docs.map((d) => Lesson.fromMap(d.data())).toList()
      ..sort((a, b) =>
          a.week != b.week ? a.week.compareTo(b.week) : a.date.compareTo(b.date));
  }

  @override
  Future<Lesson> saveLesson(Lesson l) async {
    final ref = l.id.isEmpty
        ? _db.collection('lessons').doc()
        : _db.collection('lessons').doc(l.id);
    final x = Lesson(
        id: ref.id,
        courseId: l.courseId,
        title: l.title,
        week: l.week,
        description: l.description,
        link: l.link,
        date: l.date,
        by: l.by);
    await ref.set(x.toMap());
    return x;
  }

  @override
  Future<void> deleteLesson(String id) =>
      _db.collection('lessons').doc(id).delete();

  /// معرّفات المواد تحوي "|" وهو مقبول في Firestore، لكن نستبدل "/" احتياطاً.
  static String _safe(String id) => id.replaceAll('/', '_');

  @override
  Future<void> markAttendance(AttendanceRecord r) async {
    final ref = _attendance.doc(r.id);
    final exists = (await ref.get()).exists;
    if (exists) throw AppException('${r.studentName} مسجّل حضوره مسبقاً');
    await ref.set(r.toMap());
  }

  @override
  Future<void> removeAttendance(String recordId) =>
      _attendance.doc(recordId).delete();
}
