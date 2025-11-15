import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:mopro_flutter_bindings/src/rust/frb_generated.dart';
import 'package:mopro_flutter_bindings/src/rust/third_party/spartan2_hyrax_mopro.dart'
    as rust_api;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await _copyAssetsToDocuments();
  runApp(const MyApp());
}

/// Copy circuit R1CS files and input data from Flutter assets to documents directory
Future<void> _copyAssetsToDocuments() async {
  try {
    final documentsDir = await getApplicationDocumentsDirectory();
    final circomDir = Directory('${documentsDir.path}/circom');

    if (!await circomDir.exists()) {
      await circomDir.create(recursive: true);
    }

    final compressedAssets = {
      'assets/circom/jwt.r1cs.gz': 'jwt.r1cs',
      'assets/circom/show.r1cs.gz': 'show.r1cs',
    };

    final regularAssets = [
      'assets/circom/jwt_input.json',
      'assets/circom/show_input.json',
    ];

    for (final entry in compressedAssets.entries) {
      final targetFile = File('${circomDir.path}/${entry.value}');
      if (!await targetFile.exists()) {
        debugPrint('Decompressing: ${entry.key}');
        final data = await rootBundle.load(entry.key);
        final compressed = data.buffer.asUint8List();
        final decompressed = gzip.decode(compressed);
        await targetFile.writeAsBytes(decompressed);
        debugPrint(
            'Decompressed ${entry.value}: ${(compressed.length / 1024 / 1024).toStringAsFixed(2)}MB → ${(decompressed.length / 1024 / 1024).toStringAsFixed(2)}MB');
      }
    }

    for (final assetPath in regularAssets) {
      final fileName = assetPath.split('/').last;
      final targetFile = File('${circomDir.path}/$fileName');
      if (!await targetFile.exists()) {
        debugPrint('Copying: $assetPath');
        final data = await rootBundle.load(assetPath);
        await targetFile.writeAsBytes(data.buffer.asUint8List());
      }
    }
  } catch (e) {
    debugPrint('Error copying assets: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const E2EProofWorkflowScreen(),
    );
  }
}

class E2EProofWorkflowScreen extends StatefulWidget {
  const E2EProofWorkflowScreen({super.key});

  @override
  State<E2EProofWorkflowScreen> createState() =>
      _E2EProofWorkflowScreenState();
}

enum ProofTaskType {
  setupPrepare,
  setupShow,
  generateBlinds,
  provePrepare,
  proveShow,
  reblindPrepare,
  reblindShow,
  verifyPrepare,
  verifyShow,
}

class TaskResult {
  final ProofTaskType taskType;
  final bool success;
  final String? error;
  final rust_api.ProofResult? proofResult;
  final String? message;
  final bool? verifyResult;

  TaskResult({
    required this.taskType,
    required this.success,
    this.error,
    this.proofResult,
    this.message,
    this.verifyResult,
  });

  BigInt? get totalMs => proofResult?.totalMs;
  BigInt? get proofSizeBytes => proofResult?.proofSizeBytes;
  String? get commWShared => proofResult?.commWShared;
}

class _E2EProofWorkflowScreenState extends State<E2EProofWorkflowScreen> {
  // Operation state
  bool _isOperating = false;
  Exception? _error;

  // Step results
  Map<String, TaskResult> _results = {};
  Map<String, bool> _completedSteps = {};

  // Batch operation state
  bool _isRunningBatch = false;
  String? _currentBatchStep;
  int _currentBatchStepIndex = 0;
  final List<ProofTaskType> _e2eSteps = [
    ProofTaskType.setupPrepare,
    ProofTaskType.setupShow,
    ProofTaskType.generateBlinds,
    ProofTaskType.provePrepare,
    ProofTaskType.proveShow,
    ProofTaskType.reblindPrepare,
    ProofTaskType.reblindShow,
    ProofTaskType.verifyPrepare,
    ProofTaskType.verifyShow,
  ];

  Future<String> _getDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/circom';
  }

  String? _getInputPath(ProofTaskType taskType) {
    if (taskType == ProofTaskType.setupPrepare ||
        taskType == ProofTaskType.provePrepare) {
      return 'jwt_input.json';
    } else if (taskType == ProofTaskType.setupShow ||
        taskType == ProofTaskType.proveShow) {
      return 'show_input.json';
    }
    return null;
  }

  Future<void> _runOperation(ProofTaskType taskType) async {
    setState(() {
      _isOperating = true;
      _error = null;
    });

    try {
      final documentsPath = await _getDocumentsPath();
      final inputPath = _getInputPath(taskType);
      TaskResult result;

      switch (taskType) {
        case ProofTaskType.setupPrepare:
          final message = await rust_api.setupPrepareKeys(
            documentsPath: documentsPath,
            inputPath: inputPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            message: message,
          );
          break;

        case ProofTaskType.setupShow:
          final message = await rust_api.setupShowKeys(
            documentsPath: documentsPath,
            inputPath: inputPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            message: message,
          );
          break;

        case ProofTaskType.generateBlinds:
          final message = await rust_api.generateSharedBlinds(
            documentsPath: documentsPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            message: message,
          );
          break;

        case ProofTaskType.provePrepare:
          final proofResult = await rust_api.provePrepare(
            documentsPath: documentsPath,
            inputPath: inputPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            proofResult: proofResult,
          );
          break;

        case ProofTaskType.proveShow:
          final proofResult = await rust_api.proveShow(
            documentsPath: documentsPath,
            inputPath: inputPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            proofResult: proofResult,
          );
          break;

        case ProofTaskType.reblindPrepare:
          final proofResult = await rust_api.reblindPrepare(
            documentsPath: documentsPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            proofResult: proofResult,
          );
          break;

        case ProofTaskType.reblindShow:
          final proofResult = await rust_api.reblindShow(
            documentsPath: documentsPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: true,
            proofResult: proofResult,
          );
          break;

        case ProofTaskType.verifyPrepare:
          final verifyResult = await rust_api.verifyPrepare(
            documentsPath: documentsPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: verifyResult,
            verifyResult: verifyResult,
          );
          break;

        case ProofTaskType.verifyShow:
          final verifyResult = await rust_api.verifyShow(
            documentsPath: documentsPath,
          );
          result = TaskResult(
            taskType: taskType,
            success: verifyResult,
            verifyResult: verifyResult,
          );
          break;
      }

      setState(() {
        _results[taskType.name] = result;
        _completedSteps[taskType.name] = result.success;
        _isOperating = false;
      });
    } catch (e) {
      setState(() {
        final result = TaskResult(
          taskType: taskType,
          success: false,
          error: e.toString(),
        );
        _results[taskType.name] = result;
        _completedSteps[taskType.name] = false;
        _error = Exception('${_taskTypeToDisplayName(taskType)} failed: $e');
        _isOperating = false;
        _isRunningBatch = false;
        _currentBatchStep = null;
      });
    }
  }

  Future<void> _runCompleteE2EWorkflow() async {
    setState(() {
      _isRunningBatch = true;
      _isOperating = true;
      _error = null;
      _results = {};
      _completedSteps = {};
      _currentBatchStepIndex = 0;
      _currentBatchStep = _taskTypeToDisplayName(_e2eSteps[0]);
    });

    try {
      for (int i = 0; i < _e2eSteps.length; i++) {
        final taskType = _e2eSteps[i];

        setState(() {
          _currentBatchStepIndex = i;
          _currentBatchStep = _taskTypeToDisplayName(taskType);
        });

        await _runOperation(taskType);

        // Check if the operation failed
        final result = _results[taskType.name];
        if (result != null && !result.success) {
          setState(() {
            _isRunningBatch = false;
            _isOperating = false;
            _currentBatchStep = null;
          });
          return;
        }
      }

      setState(() {
        _isRunningBatch = false;
        _isOperating = false;
        _currentBatchStep = null;
      });
    } catch (e) {
      setState(() {
        _error = Exception('E2E workflow failed: $e');
        _isRunningBatch = false;
        _isOperating = false;
        _currentBatchStep = null;
      });
    }
  }

  void _reset() {
    setState(() {
      _results = {};
      _completedSteps = {};
      _error = null;
      _isOperating = false;
      _isRunningBatch = false;
      _currentBatchStep = null;
    });
  }

  String _taskTypeToDisplayName(ProofTaskType type) {
    return switch (type) {
      ProofTaskType.setupPrepare => 'Setup Prepare Keys',
      ProofTaskType.setupShow => 'Setup Show Keys',
      ProofTaskType.generateBlinds => 'Generate Shared Blinds',
      ProofTaskType.provePrepare => 'Prove Prepare',
      ProofTaskType.proveShow => 'Prove Show',
      ProofTaskType.reblindPrepare => 'Reblind Prepare',
      ProofTaskType.reblindShow => 'Reblind Show',
      ProofTaskType.verifyPrepare => 'Verify Prepare',
      ProofTaskType.verifyShow => 'Verify Show',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('zkID E2E Proof Workflow'),
        actions: [
          if (_results.isNotEmpty && !_isOperating)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reset,
              tooltip: 'Reset',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error.toString(),
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _error = null),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Complete E2E Workflow Button
            Card(
              elevation: 4,
              color: Colors.purple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.playlist_play,
                            color: Colors.purple.shade700, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Complete E2E Workflow',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Execute all 9 steps sequentially: Setup → Generate Blinds → Prove → Reblind → Verify',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isRunningBatch && _currentBatchStep != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Progress: Step ${_currentBatchStepIndex + 1}/${_e2eSteps.length}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current: $_currentBatchStep',
                              style: TextStyle(color: Colors.purple.shade700),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _currentBatchStepIndex / _e2eSteps.length,
                              backgroundColor: Colors.purple.shade100,
                              valueColor: AlwaysStoppedAnimation(
                                  Colors.purple.shade700),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isOperating ? null : _runCompleteE2EWorkflow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _isRunningBatch
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_isRunningBatch
                            ? 'Running...'
                            : 'Run Complete E2E Workflow'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Step 1: Setup Operations
            _buildSectionHeader('Step 1: Setup Operations', Icons.settings),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.setupPrepare,
                    label: 'Setup Prepare',
                    icon: Icons.key,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.setupShow,
                    label: 'Setup Show',
                    icon: Icons.key,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Step 2: Generate Shared Blinds
            _buildSectionHeader(
                'Step 2: Generate Shared Blinds', Icons.shuffle),
            const SizedBox(height: 12),
            _buildOperationButton(
              taskType: ProofTaskType.generateBlinds,
              label: 'Generate Shared Blinds',
              icon: Icons.shuffle,
              color: Colors.orange,
            ),

            const SizedBox(height: 24),

            // Step 3: Prove Operations
            _buildSectionHeader('Step 3: Prove Operations', Icons.calculate),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.provePrepare,
                    label: 'Prove Prepare',
                    icon: Icons.calculate,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.proveShow,
                    label: 'Prove Show',
                    icon: Icons.calculate,
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Step 4: Reblind Operations
            _buildSectionHeader('Step 4: Reblind Operations', Icons.sync),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.reblindPrepare,
                    label: 'Reblind Prepare',
                    icon: Icons.sync,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.reblindShow,
                    label: 'Reblind Show',
                    icon: Icons.sync,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Step 5: Verify Operations
            _buildSectionHeader('Step 5: Verify Operations', Icons.check_circle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.verifyPrepare,
                    label: 'Verify Prepare',
                    icon: Icons.check_circle,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOperationButton(
                    taskType: ProofTaskType.verifyShow,
                    label: 'Verify Show',
                    icon: Icons.check_circle,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Results Display
            if (_results.isNotEmpty) ...[
              _buildSectionHeader('Results', Icons.assessment),
              const SizedBox(height: 12),
              ..._results.entries
                  .map((entry) => _buildResultCard(entry.key, entry.value)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _buildOperationButton({
    required ProofTaskType taskType,
    required String label,
    required IconData icon,
    required MaterialColor color,
  }) {
    final isCompleted = _completedSteps[taskType.name] == true;
    final result = _results[taskType.name];

    return ElevatedButton.icon(
      onPressed: _isOperating ? null : () => _runOperation(taskType),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCompleted ? color.shade100 : color,
        foregroundColor: isCompleted ? color.shade900 : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      icon:
          isCompleted ? Icon(Icons.check_circle, color: color.shade700) : Icon(icon),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (result?.totalMs != null)
            Text(
              '${result!.totalMs}ms',
              style: TextStyle(
                fontSize: 11,
                color: isCompleted ? color.shade700 : Colors.white70,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultCard(String taskName, TaskResult result) {
    final taskType =
        ProofTaskType.values.firstWhere((e) => e.name == taskName);
    final displayName = _taskTypeToDisplayName(taskType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success ? Icons.check_circle : Icons.error,
                  color: result.success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Error message
            if (result.error != null) ...[
              Text(
                'Error: ${result.error}',
                style: TextStyle(color: Colors.red.shade700),
              ),
              const SizedBox(height: 8),
            ],

            // Success message
            if (result.message != null) ...[
              Text(result.message!),
              const SizedBox(height: 8),
            ],

            // Timings
            if (result.totalMs != null) ...[
              const Text(
                'Timing:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('• Total: ${result.totalMs}ms'),
              const SizedBox(height: 8),
            ],

            // Proof size
            if (result.proofSizeBytes != null) ...[
              Text(
                'Proof Size: ${(result.proofSizeBytes!.toInt() / 1024).toStringAsFixed(2)} KB',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
            ],

            // Shared commitment
            if (result.commWShared != null) ...[
              const Text(
                'Shared Commitment:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  result.commWShared!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],

            // Verification result
            if (result.verifyResult != null) ...[
              const SizedBox(height: 8),
              Text(
                result.verifyResult! ? 'Verification passed ✓' : 'Verification failed ✗',
                style: TextStyle(
                  color: result.verifyResult!
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
