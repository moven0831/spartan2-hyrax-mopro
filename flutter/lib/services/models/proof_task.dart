/// Represents a proof generation task to be executed in the background service
class ProofTask {
  final String id;
  final ProofTaskType type;
  final Map<String, dynamic> params;
  final DateTime createdAt;
  TaskStatus status;
  DateTime? startedAt;
  DateTime? completedAt;

  ProofTask({
    required this.id,
    required this.type,
    required this.params,
    DateTime? createdAt,
    this.status = TaskStatus.queued,
    this.startedAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convert task to JSON for service communication
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'params': params,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'status': status.name,
      'startedAt': startedAt?.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
    };
  }

  /// Create task from JSON received from service
  factory ProofTask.fromJson(Map<String, dynamic> json) {
    return ProofTask(
      id: json['id'] as String,
      type: ProofTaskType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      params: Map<String, dynamic>.from(json['params'] as Map),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      status: TaskStatus.values.firstWhere(
        (e) => e.name == json['status'],
      ),
      startedAt: json['startedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['completedAt'] as int)
          : null,
    );
  }

  /// Get duration in milliseconds if task is completed
  int? get durationMs {
    if (startedAt != null && completedAt != null) {
      return completedAt!.difference(startedAt!).inMilliseconds;
    }
    return null;
  }

  @override
  String toString() {
    return 'ProofTask(id: $id, type: ${type.name}, status: ${status.name})';
  }
}

/// Types of proof operations that can be executed
enum ProofTaskType {
  setupPrepare,
  setupShow,
  provePrepare,
}

/// Task execution status
enum TaskStatus {
  queued,
  running,
  completed,
  failed,
}
