import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get currentUserId {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('No authenticated user found.');
    return user.id;
  }

  Future<int> timeIn() => _runAction('clock_in');
  Future<int> breakIn() => _runAction('start_break');
  Future<int> breakOut() => _runAction('end_break');
  Future<int> timeOut() => _runAction('clock_out');

  Future<int> _runAction(String functionName) async {
    final response = await _supabase.rpc(functionName);
    return _attendanceId(Map<String, dynamic>.from(response as Map));
  }

  Future<Map<String, dynamic>?> getTodayAttendance() async {
    final response = await _supabase.rpc('get_current_attendance');
    if (response == null) return null;
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> getMonthlyPaySummary() async {
    final response = await _supabase.rpc('get_my_monthly_pay_summary');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> getAttendanceHistory() async {
    final response = await _supabase
        .from('attendance')
        .select()
        .eq('user_id', currentUserId)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  int _attendanceId(Map<String, dynamic>? attendance) {
    final id = attendance?['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    throw StateError('Supabase did not return an attendance record ID.');
  }
}
