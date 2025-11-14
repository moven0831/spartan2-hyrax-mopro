import 'proof_task.dart';

export 'proof_task.dart' show ProofTaskType;

/// Represents the result of a completed proof operation with timing metrics
class ProofResult {
  final String taskId;
  final ProofTaskType taskType;
  final bool success;
  final String? rawResult;
  final String? error;
  final ProofTimings? timings;
  final DateTime completedAt;

  ProofResult({
    required this.taskId,
    required this.taskType,
    required this.success,
    this.rawResult,
    this.error,
    this.timings,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  /// Convert result to JSON for service communication
  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'taskType': taskType.name,
      'success': success,
      'rawResult': rawResult,
      'error': error,
      'timings': timings?.toJson(),
      'completedAt': completedAt.millisecondsSinceEpoch,
    };
  }

  /// Create result from JSON received from service
  factory ProofResult.fromJson(Map<String, dynamic> json) {
    return ProofResult(
      taskId: json['taskId'] as String,
      taskType: ProofTaskType.values.firstWhere(
        (e) => e.name == json['taskType'],
      ),
      success: json['success'] as bool,
      rawResult: json['rawResult'] as String?,
      error: json['error'] as String?,
      timings: json['timings'] != null
          ? ProofTimings.fromJson(json['timings'] as Map<String, dynamic>)
          : null,
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        json['completedAt'] as int,
      ),
    );
  }

  /// Parse timing metrics from raw Rust output string
  /// Example: "circuit completed | Setup: 92ms | Prep: 2ms | Prove: 89ms | Verify: 11ms | Total: 194ms"
  factory ProofResult.fromRustOutput({
    required String taskId,
    required ProofTaskType taskType,
    required String rustOutput,
  }) {
    final timings = ProofTimings.fromRustOutput(rustOutput);
    return ProofResult(
      taskId: taskId,
      taskType: taskType,
      success: true,
      rawResult: rustOutput,
      timings: timings,
    );
  }

  /// Create a failed result with error message
  factory ProofResult.failed({
    required String taskId,
    required ProofTaskType taskType,
    required String error,
  }) {
    return ProofResult(
      taskId: taskId,
      taskType: taskType,
      success: false,
      error: error,
    );
  }

  @override
  String toString() {
    if (success) {
      return 'ProofResult(taskId: $taskId, type: ${taskType.name}, timings: $timings)';
    } else {
      return 'ProofResult(taskId: $taskId, type: ${taskType.name}, error: $error)';
    }
  }
}

/// Timing metrics extracted from proof operation
class ProofTimings {
  final int? setupMs;
  final int? prepMs;
  final int? proveMs;
  final int? verifyMs;
  final int totalMs;

  ProofTimings({
    this.setupMs,
    this.prepMs,
    this.proveMs,
    this.verifyMs,
    required this.totalMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'setupMs': setupMs,
      'prepMs': prepMs,
      'proveMs': proveMs,
      'verifyMs': verifyMs,
      'totalMs': totalMs,
    };
  }

  factory ProofTimings.fromJson(Map<String, dynamic> json) {
    return ProofTimings(
      setupMs: json['setupMs'] as int?,
      prepMs: json['prepMs'] as int?,
      proveMs: json['proveMs'] as int?,
      verifyMs: json['verifyMs'] as int?,
      totalMs: json['totalMs'] as int,
    );
  }

  /// Parse timings from Rust output string
  /// Handles multiple formats:
  /// 1. Full circuit: "circuit completed | Setup: 92ms | Prep: 2ms | Prove: 89ms | Verify: 11ms | Total: 194ms"
  /// 2. Setup only: "Prepare circuit keys setup completed in 12345ms"
  /// 3. Prove only: "proof completed | Prep: 2ms | Prove: 89ms | Total: 91ms"
  factory ProofTimings.fromRustOutput(String output) {
    // Check for setup-only format first
    final setupOnlyMatch = RegExp(r'circuit keys setup completed in (\d+)ms').firstMatch(output);
    if (setupOnlyMatch != null) {
      final timeMs = int.parse(setupOnlyMatch.group(1)!);
      return ProofTimings(
        setupMs: timeMs,
        totalMs: timeMs,
      );
    }

    // Parse standard format with multiple phases
    final setupMatch = RegExp(r'Setup:\s*(\d+)ms').firstMatch(output);
    final prepMatch = RegExp(r'Prep:\s*(\d+)ms').firstMatch(output);
    final proveMatch = RegExp(r'Prove:\s*(\d+)ms').firstMatch(output);
    final verifyMatch = RegExp(r'Verify:\s*(\d+)ms').firstMatch(output);
    final totalMatch = RegExp(r'Total:\s*(\d+)ms').firstMatch(output);

    return ProofTimings(
      setupMs: setupMatch != null ? int.parse(setupMatch.group(1)!) : null,
      prepMs: prepMatch != null ? int.parse(prepMatch.group(1)!) : null,
      proveMs: proveMatch != null ? int.parse(proveMatch.group(1)!) : null,
      verifyMs: verifyMatch != null ? int.parse(verifyMatch.group(1)!) : null,
      totalMs: totalMatch != null ? int.parse(totalMatch.group(1)!) : 0,
    );
  }

  /// Format timings as a human-readable string
  String toDisplayString() {
    final parts = <String>[];
    if (setupMs != null) parts.add('Setup: ${setupMs}ms');
    if (prepMs != null) parts.add('Prep: ${prepMs}ms');
    if (proveMs != null) parts.add('Prove: ${proveMs}ms');
    if (verifyMs != null) parts.add('Verify: ${verifyMs}ms');
    parts.add('Total: ${totalMs}ms');
    return parts.join(' | ');
  }

  @override
  String toString() => toDisplayString();
}
