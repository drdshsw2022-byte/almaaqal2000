int asInt(dynamic v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? def;
}

double asDouble(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? def;
}

String? asStrOrNull(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

List<String> asStrList(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : <String>[];

/// الصفات بالتسلسل الهرمي.
/// admin: مدير النظام • president: الإدارة العليا (رئيس الجامعة/مجلس الأمناء)
/// dean: عميد كلية • head: رئيس قسم • doctor: تدريسي • student: طالب
enum Role { admin, president, dean, head, doctor, student }

const staffRoles = ['president', 'dean', 'head', 'doctor', 'admin'];

const roleNames = {
  'admin': 'مدير النظام',
  'president': 'الإدارة العليا',
  'dean': 'عميد كلية',
  'head': 'رئيس قسم',
  'doctor': 'تدريسي',
  'student': 'طالب',
};
String roleName(String r) => roleNames[r] ?? r;

Role roleFrom(String r) => switch (r) {
      'admin' => Role.admin,
      'president' => Role.president,
      'dean' => Role.dean,
      'head' => Role.head,
      _ => Role.doctor,
    };

/// الإدارة (تدخل من تبويب الإدارة).
bool isManagement(Role r) =>
    r == Role.admin || r == Role.president || r == Role.dean || r == Role.head;

const stageNames = {
  1: 'المرحلة الأولى',
  2: 'المرحلة الثانية',
  3: 'المرحلة الثالثة',
  4: 'المرحلة الرابعة',
  5: 'المرحلة الخامسة',
};

String stageName(int s) => stageNames[s] ?? 'المرحلة $s';

const shiftNames = {'morning': 'صباحي', 'evening': 'مسائي', 'all': 'الكل'};
String shiftName(String s) => shiftNames[s] ?? s;
String termName(int t) => t == 1 ? 'الكورس الأول' : 'الكورس الثاني';

class College {
  final String id;
  final String name;
  College({required this.id, required this.name});
  Map<String, dynamic> toMap() => {'id': id, 'name': name};
  factory College.fromMap(Map<String, dynamic> m) =>
      College(id: '${m['id']}', name: '${m['name'] ?? ''}');
}

class Department {
  final String id;
  final String name;
  final String collegeId;
  Department({required this.id, required this.name, required this.collegeId});
  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'collegeId': collegeId};
  factory Department.fromMap(Map<String, dynamic> m) => Department(
      id: '${m['id']}',
      name: '${m['name'] ?? ''}',
      collegeId: '${m['collegeId'] ?? ''}');
}

class Course {
  final String id;
  final String deptId;
  final int semester; // 1..8
  final int stage; // 1..4
  final int term; // 1 أو 2
  final String code;
  final String nameAr;
  final String nameEn;
  final int ects;
  final int credits; // الساعات المعتمدة
  final List<String> prereqs; // رموز المتطلبات السابقة

  Course({
    required this.id,
    required this.deptId,
    required this.semester,
    required this.stage,
    required this.term,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.ects,
    this.credits = 0,
    this.prereqs = const [],
  });

  static String makeId(String deptId, int semester, String code) =>
      '$deptId|$semester|$code';

  Map<String, dynamic> toMap() => {
        'id': id,
        'deptId': deptId,
        'semester': semester,
        'stage': stage,
        'term': term,
        'code': code,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'ects': ects,
        'credits': credits,
        'prereqs': prereqs,
      };

  factory Course.fromMap(Map<String, dynamic> m) {
    final sem = asInt(m['semester'], 1);
    return Course(
      id: '${m['id']}',
      deptId: '${m['deptId'] ?? ''}',
      semester: sem,
      stage: asInt(m['stage'], (sem + 1) ~/ 2),
      term: asInt(m['term'], sem.isOdd ? 1 : 2),
      code: '${m['code'] ?? ''}',
      nameAr: '${m['nameAr'] ?? ''}',
      nameEn: '${m['nameEn'] ?? ''}',
      ects: asInt(m['ects']),
      credits: asInt(m['credits']),
      prereqs: asStrList(m['prereqs']),
    );
  }
}

class Student {
  final String id; // الرقم المعرفي
  final String name;
  final int stage;
  final String shift; // morning | evening
  final String? deptId;
  final String? email; // البريد الجامعي الرسمي
  final String? nfcUid; // معرّف شريحة NFC في الهوية الجامعية
  final bool activated; // سجّل الدخول وغيّر كلمة المرور الأولية
  final String? initPw; // بصمة كلمة المرور الأولية (إن حددها المدير)

  Student({
    required this.id,
    required this.name,
    required this.stage,
    required this.shift,
    this.deptId,
    this.email,
    this.nfcUid,
    this.activated = false,
    this.initPw,
  });

  Student copyWith({
    String? name,
    int? stage,
    String? shift,
    String? deptId,
    bool clearDept = false,
    String? email,
    bool clearEmail = false,
    String? nfcUid,
    bool clearNfc = false,
    bool? activated,
    String? initPw,
  }) =>
      Student(
        id: id,
        name: name ?? this.name,
        stage: stage ?? this.stage,
        shift: shift ?? this.shift,
        deptId: clearDept ? null : (deptId ?? this.deptId),
        email: clearEmail ? null : (email ?? this.email),
        nfcUid: clearNfc ? null : (nfcUid ?? this.nfcUid),
        activated: activated ?? this.activated,
        initPw: initPw ?? this.initPw,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'stage': stage,
        'shift': shift,
        'deptId': deptId,
        'email': email,
        'nfcUid': nfcUid,
        'activated': activated,
        'initPw': initPw,
      };

  factory Student.fromMap(Map<String, dynamic> m) => Student(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        stage: asInt(m['stage'], 1),
        shift: '${m['shift'] ?? 'morning'}',
        deptId: asStrOrNull(m['deptId']),
        email: asStrOrNull(m['email'])?.toLowerCase(),
        nfcUid: asStrOrNull(m['nfcUid'])?.toUpperCase(),
        activated: m['activated'] == true,
        initPw: asStrOrNull(m['initPw']),
      );
}

/// عضو الكادر. المعرّف = البريد الجامعي (بأحرف صغيرة).
class Staff {
  final String id; // البريد الجامعي
  final String name;
  final String role; // admin | president | dean | head | doctor
  final String? collegeId; // للعميد
  final String? deptId; // لرئيس القسم والتدريسي
  final List<String> courseIds;
  final bool activated;
  final String? initPw;
  final String? alias; // اسم مستخدم مختار (مثل doc01) بدل بداية البريد

  Staff({
    required String id,
    required this.name,
    required this.role,
    this.collegeId,
    this.deptId,
    this.courseIds = const [],
    this.activated = false,
    this.initPw,
    String? alias,
  })  : id = id.trim().toLowerCase(),
        alias = (alias == null || alias.trim().isEmpty)
            ? null
            : alias.trim().toLowerCase();

  /// اسم المستخدم المعروض للدخول.
  String get loginName => alias ?? username;

  /// اسم المستخدم = الجزء قبل @ من البريد الجامعي.
  String get username => id.split('@').first;

  bool get isAdmin => role == 'admin';
  Role get roleEnum => roleFrom(role);
  String get email => id;

  Staff copyWith({
    String? name,
    String? role,
    String? collegeId,
    String? deptId,
    List<String>? courseIds,
    bool? activated,
    String? initPw,
    String? alias,
  }) =>
      Staff(
        id: id,
        alias: alias ?? this.alias,
        name: name ?? this.name,
        role: role ?? this.role,
        collegeId: collegeId ?? this.collegeId,
        deptId: deptId ?? this.deptId,
        courseIds: courseIds ?? this.courseIds,
        activated: activated ?? this.activated,
        initPw: initPw ?? this.initPw,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': id,
        'name': name,
        'role': role,
        'collegeId': collegeId,
        'deptId': deptId,
        'courseIds': courseIds,
        'activated': activated,
        'initPw': initPw,
        'alias': alias,
      };

  factory Staff.fromMap(Map<String, dynamic> m) => Staff(
        id: '${m['id'] ?? m['email']}',
        name: '${m['name'] ?? ''}',
        role: '${m['role'] ?? 'doctor'}',
        collegeId: asStrOrNull(m['collegeId']),
        deptId: asStrOrNull(m['deptId']),
        courseIds: asStrList(m['courseIds']),
        activated: m['activated'] == true,
        initPw: asStrOrNull(m['initPw']),
        alias: asStrOrNull(m['alias']),
      );
}

class AppUser {
  final Role role;
  final Student? student;
  final Staff? staff;
  AppUser.student(Student s)
      : role = Role.student,
        student = s,
        staff = null;
  AppUser.staff(Staff s)
      : role = s.roleEnum,
        staff = s,
        student = null;

  String get id => student?.id ?? staff!.id;
  String get name => student?.name ?? staff!.name;
  String? get email => student?.email ?? staff?.email;
  String get displayId => student?.id ?? staff!.email;
}

class LectureSession {
  final String id;
  final String courseId;
  final String courseName;
  final String deptId;
  final int stage;
  final String shift; // all | morning | evening
  final String doctorId;
  final String doctorName;
  final String title;
  final int startedAt; // ms
  final int? endedAt;
  final bool active;

  LectureSession({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.deptId,
    required this.stage,
    required this.shift,
    required this.doctorId,
    required this.doctorName,
    required this.title,
    required this.startedAt,
    this.endedAt,
    this.active = true,
  });

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(startedAt);

  LectureSession copyWith({String? id, bool? active, int? endedAt}) =>
      LectureSession(
        id: id ?? this.id,
        courseId: courseId,
        courseName: courseName,
        deptId: deptId,
        stage: stage,
        shift: shift,
        doctorId: doctorId,
        doctorName: doctorName,
        title: title,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        active: active ?? this.active,
      );

  /// هل يخص هذا الطالب هذه المحاضرة؟
  bool appliesTo(Student s) =>
      s.stage == stage &&
      (shift == 'all' || shift == s.shift) &&
      (s.deptId == null || s.deptId == deptId);

  Map<String, dynamic> toMap() => {
        'id': id,
        'courseId': courseId,
        'courseName': courseName,
        'deptId': deptId,
        'stage': stage,
        'shift': shift,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'title': title,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'active': active,
      };

  factory LectureSession.fromMap(Map<String, dynamic> m) => LectureSession(
        id: '${m['id']}',
        courseId: '${m['courseId'] ?? ''}',
        courseName: '${m['courseName'] ?? ''}',
        deptId: '${m['deptId'] ?? ''}',
        stage: asInt(m['stage'], 1),
        shift: '${m['shift'] ?? 'all'}',
        doctorId: '${m['doctorId'] ?? ''}',
        doctorName: '${m['doctorName'] ?? ''}',
        title: '${m['title'] ?? ''}',
        startedAt: asInt(m['startedAt']),
        endedAt: m['endedAt'] == null ? null : asInt(m['endedAt']),
        active: m['active'] == true,
      );
}

class AttendanceRecord {
  final String id; // sessionId_studentId
  final String sessionId;
  final String courseId;
  final String studentId;
  final String studentName;
  final int time;
  final String method; // qr | nfc | manual

  AttendanceRecord({
    required this.sessionId,
    required this.courseId,
    required this.studentId,
    required this.studentName,
    required this.time,
    required this.method,
  }) : id = '${sessionId}_$studentId';

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(time);

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'courseId': courseId,
        'studentId': studentId,
        'studentName': studentName,
        'time': time,
        'method': method,
      };

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) => AttendanceRecord(
        sessionId: '${m['sessionId'] ?? ''}',
        courseId: '${m['courseId'] ?? ''}',
        studentId: '${m['studentId'] ?? ''}',
        studentName: '${m['studentName'] ?? ''}',
        time: asInt(m['time']),
        method: '${m['method'] ?? 'qr'}',
      );
}

class AppSettings {
  final int currentTerm;
  final double warnPercent;
  final double failPercent;

  const AppSettings({
    this.currentTerm = 1,
    this.warnPercent = 10,
    this.failPercent = 15,
  });

  Map<String, dynamic> toMap() => {
        'currentTerm': currentTerm,
        'warnPercent': warnPercent,
        'failPercent': failPercent,
      };

  factory AppSettings.fromMap(Map<String, dynamic>? m) => m == null
      ? const AppSettings()
      : AppSettings(
          currentTerm: asInt(m['currentTerm'], 1),
          warnPercent: asDouble(m['warnPercent'], 10),
          failPercent: asDouble(m['failPercent'], 15),
        );
}

/// ملخص حضور طالب في مادة.
class StudentCourseStat {
  final Student student;
  final int total;
  final int present;
  StudentCourseStat(this.student, this.total, this.present);
  int get absent => total - present;
  double get absencePercent => total == 0 ? 0 : absent * 100 / total;
  double get attendancePercent => total == 0 ? 100 : present * 100 / total;
}

class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

/// يُرمى عند تسجيل الدخول ببريد غير مسجّل في قاعدة البيانات.
class NotRegisteredException extends AppException {
  final String email;
  NotRegisteredException(this.email)
      : super('البريد $email غير مسجّل في نظام الحضور. راجع إدارة القسم لإضافته');
}

String methodName(String m) => switch (m) {
      'qr' => 'QR',
      'nfc' => 'NFC',
      'id' => 'الرقم الجامعي',
      _ => 'يدوي',
    };

/// نتيجة تسجيل الدخول.
class LoginResult {
  final AppUser user;
  final bool mustChangePassword;
  LoginResult(this.user, {this.mustChangePassword = false});
}

// ======================== الدرجات ========================

/// مكوّنات الدرجة بالترتيب (مطابقة لسجل درجات الجامعة student_grades_full).
const gradeComponents = [
  'attendance',
  'assignment',
  'project',
  'lab',
  'quiz',
  'midterm',
  'final'
];

const gradeComponentNames = {
  'attendance': 'الحضور',
  'assignment': 'الواجب البيتي',
  'project': 'المشروع',
  'lab': 'المختبر',
  'quiz': 'الامتحان الأسبوعي',
  'midterm': 'الامتحان الفصلي',
  'final': 'الامتحان النهائي',
};
String componentName(String k) => gradeComponentNames[k] ?? k;

const gradeComponentNamesEn = {
  'attendance': 'Attendance',
  'assignment': 'Homework',
  'project': 'Project',
  'lab': 'Lab',
  'quiz': 'Weekly Quiz',
  'midterm': 'Midterm',
  'final': 'Final Exam (1st)',
};

/// الدرجات القصوى الافتراضية (50 سعي + 50 نهائي) كما في سجل الجامعة.
const defaultMax = {
  'attendance': 5.0,
  'assignment': 5.0,
  'project': 10.0,
  'lab': 10.0,
  'quiz': 10.0,
  'midterm': 10.0,
  'final': 50.0,
};

/// توزيع درجات مادة + ما نُشر منها للطلبة.
class GradeScheme {
  final String courseId;
  final Map<String, double> max;
  final Set<String> published;
  GradeScheme({required this.courseId, Map<String, double>? max, Set<String>? published})
      : max = max ?? Map.of(defaultMax),
        published = published ?? <String>{};

  double get total =>
      gradeComponents.fold<double>(0, (a, k) => a + (max[k] ?? 0));
  List<String> get active => gradeComponents.where((k) => (max[k] ?? 0) > 0).toList();

  Map<String, dynamic> toMap() => {
        'id': courseId,
        'courseId': courseId,
        'max': max,
        'published': published.toList(),
      };

  factory GradeScheme.fromMap(String courseId, Map<String, dynamic>? m) {
    if (m == null) return GradeScheme(courseId: courseId);
    final mx = <String, double>{};
    (m['max'] as Map? ?? {}).forEach((k, v) => mx['$k'] = asDouble(v));
    return GradeScheme(
      courseId: courseId,
      max: mx.isEmpty ? null : mx,
      published: asStrList(m['published']).toSet(),
    );
  }
}

/// درجات طالب في مادة.
class GradeRecord {
  final String courseId;
  final String studentId;
  final String studentName;
  final String? studentEmail;
  final Map<String, double> marks;
  final int updatedAt;

  GradeRecord({
    required this.courseId,
    required this.studentId,
    required this.studentName,
    this.studentEmail,
    Map<String, double>? marks,
    int? updatedAt,
  })  : marks = marks ?? {},
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  String get id => '${courseId}_$studentId';

  double totalOf(Iterable<String> comps) =>
      comps.fold(0.0, (a, k) => a + (marks[k] ?? 0));

  Map<String, dynamic> toMap() => {
        'id': id,
        'courseId': courseId,
        'studentId': studentId,
        'studentName': studentName,
        'studentEmail': studentEmail,
        'marks': marks,
        'updatedAt': updatedAt,
      };

  factory GradeRecord.fromMap(Map<String, dynamic> m) {
    final mk = <String, double>{};
    (m['marks'] as Map? ?? {}).forEach((k, v) {
      if (v != null) mk['$k'] = asDouble(v);
    });
    return GradeRecord(
      courseId: '${m['courseId'] ?? ''}',
      studentId: '${m['studentId'] ?? ''}',
      studentName: '${m['studentName'] ?? ''}',
      studentEmail: asStrOrNull(m['studentEmail']),
      marks: mk,
      updatedAt: asInt(m['updatedAt']),
    );
  }
}

/// التقدير حسب النظام العراقي.
({String label, bool pass}) gradeLetter(double total) {
  if (total >= 90) return (label: 'امتياز', pass: true);
  if (total >= 80) return (label: 'جيد جداً', pass: true);
  if (total >= 70) return (label: 'جيد', pass: true);
  if (total >= 60) return (label: 'متوسط', pass: true);
  if (total >= 50) return (label: 'مقبول', pass: true);
  return (label: 'راسب', pass: false);
}

// ======================== الدروس ========================

class Lesson {
  final String id;
  final String courseId;
  final String title;
  final int week;
  final String description;
  final String? link;
  final int date;
  final String by;

  Lesson({
    required this.id,
    required this.courseId,
    required this.title,
    this.week = 1,
    this.description = '',
    this.link,
    int? date,
    this.by = '',
  }) : date = date ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'courseId': courseId,
        'title': title,
        'week': week,
        'description': description,
        'link': link,
        'date': date,
        'by': by,
      };

  factory Lesson.fromMap(Map<String, dynamic> m) => Lesson(
        id: '${m['id']}',
        courseId: '${m['courseId'] ?? ''}',
        title: '${m['title'] ?? ''}',
        week: asInt(m['week'], 1),
        description: '${m['description'] ?? ''}',
        link: asStrOrNull(m['link']),
        date: asInt(m['date']),
        by: '${m['by'] ?? ''}',
      );
}
