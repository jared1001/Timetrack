import 'package:supabase_flutter/supabase_flutter.dart';

class LeaveRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get currentUserId {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated user found.');
    }

    return user.id;
  }

  Future<void> createRequest({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _supabase.from('leave_requests').insert({
      'user_id': currentUserId,
      'leave_type': leaveType,
      'start_date': _dateValue(startDate),
      'end_date': _dateValue(endDate),
      'reason': reason.trim().isEmpty ? null : reason.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> getMyRequests() async {
    final response = await _supabase
        .from('leave_requests')
        .select('id, leave_type, start_date, end_date, reason, status, created_at')
        .eq('user_id', currentUserId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  String _dateValue(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
