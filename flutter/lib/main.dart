import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:mopro_flutter_bindings/src/rust/third_party/spartan2_hyrax_mopro.dart';
import 'package:mopro_flutter_bindings/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await _copyAssetsToDocuments();
  runApp(const MyApp());
}

/// Copy circuit R1CS files and input data from Flutter assets to documents directory
/// This allows Rust code to access them at runtime
/// Compressed .gz files are automatically decompressed during copying
Future<void> _copyAssetsToDocuments() async {
  try {
    final documentsDir = await getApplicationDocumentsDirectory();
    final circomDir = Directory('${documentsDir.path}/circom');

    // Create circom directory if it doesn't exist
    if (!await circomDir.exists()) {
      await circomDir.create(recursive: true);
    }

    // Compressed assets (will be decompressed during copy)
    final compressedAssets = {
      'assets/circom/jwt.r1cs.gz': 'jwt.r1cs',
      'assets/circom/show.r1cs.gz': 'show.r1cs',
    };

    // Regular assets (copied as-is)
    final regularAssets = [
      'assets/circom/jwt_input.json',
      'assets/circom/show_input.json',
    ];

    // Decompress and copy compressed assets
    for (final entry in compressedAssets.entries) {
      final assetPath = entry.key;
      final fileName = entry.value;
      final targetFile = File('${circomDir.path}/$fileName');

      // Only copy if file doesn't exist (avoid overwriting on every startup)
      if (!await targetFile.exists()) {
        debugPrint('Decompressing asset: $assetPath -> ${targetFile.path}');
        try {
          final data = await rootBundle.load(assetPath);
          final compressed = data.buffer.asUint8List();

          // Decompress using gzip
          final decompressed = gzip.decode(compressed);
          await targetFile.writeAsBytes(decompressed);

          final compressedMB = (compressed.length / 1024 / 1024).toStringAsFixed(2);
          final decompressedMB = (decompressed.length / 1024 / 1024).toStringAsFixed(2);
          debugPrint('Decompressed $fileName: ${compressedMB}MB -> ${decompressedMB}MB');
        } catch (e) {
          debugPrint('Failed to decompress $assetPath: $e');
          rethrow;
        }
      }
    }

    // Copy regular assets (no decompression needed)
    for (final assetPath in regularAssets) {
      final fileName = assetPath.split('/').last;
      final targetFile = File('${circomDir.path}/$fileName');

      if (!await targetFile.exists()) {
        debugPrint('Copying asset: $assetPath -> ${targetFile.path}');
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        await targetFile.writeAsBytes(bytes);
        debugPrint('Copied $fileName (${bytes.length} bytes)');
      }
    }
  } catch (e) {
    debugPrint('Error copying assets: $e');
    // Don't throw - allow app to start even if asset copying fails
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
      home: const CircuitProverScreen(),
    );
  }
}

enum CircuitType { prepare, show }

enum OperationPhase { idle, setup, proving, verifying, complete }

class CircuitProverScreen extends StatefulWidget {
  const CircuitProverScreen({super.key});

  @override
  State<CircuitProverScreen> createState() => _CircuitProverScreenState();
}

class _CircuitProverScreenState extends State<CircuitProverScreen> {
  CircuitType _selectedCircuit = CircuitType.prepare;
  OperationPhase _currentPhase = OperationPhase.idle;

  bool _isOperating = false;
  String? _setupResult;
  String? _proveResult;
  String? _fullWorkflowResult;
  Exception? _error;

  // Timing metrics (parsed from result strings)
  int? _setupTimeMs;
  int? _proveTimeMs;
  Map<String, int>? _proveTimings;
  Map<String, int>? _fullWorkflowTimings;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await initApp();
    } catch (e) {
      setState(() {
        _error = Exception('Initialization failed: $e');
      });
    }
  }

  Future<String> _getDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  int? _parseTimeFromResult(String result) {
    // Parse "completed in XXXms" from result string
    final regex = RegExp(r'(\d+)ms');
    final match = regex.firstMatch(result);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  Map<String, int>? _parseDetailedTimings(String result) {
    // Parse detailed timing format:
    // "circuit completed | Setup: 92ms | Prep: 2ms | Prove: 89ms | Verify: 11ms | Total: 194ms"
    // or "proof completed | Prep: 2ms | Prove: 89ms | Total: 91ms"
    final Map<String, int> timings = {};

    final setupMatch = RegExp(r'Setup: (\d+)ms').firstMatch(result);
    if (setupMatch != null) {
      timings['setup'] = int.parse(setupMatch.group(1)!);
    }

    final prepMatch = RegExp(r'Prep: (\d+)ms').firstMatch(result);
    if (prepMatch != null) {
      timings['prep'] = int.parse(prepMatch.group(1)!);
    }

    final proveMatch = RegExp(r'Prove: (\d+)ms').firstMatch(result);
    if (proveMatch != null) {
      timings['prove'] = int.parse(proveMatch.group(1)!);
    }

    final verifyMatch = RegExp(r'Verify: (\d+)ms').firstMatch(result);
    if (verifyMatch != null) {
      timings['verify'] = int.parse(verifyMatch.group(1)!);
    }

    final totalMatch = RegExp(r'Total: (\d+)ms').firstMatch(result);
    if (totalMatch != null) {
      timings['total'] = int.parse(totalMatch.group(1)!);
    }

    final proofMatch = RegExp(r'Proof: (\d+) bytes').firstMatch(result);
    if (proofMatch != null) {
      timings['proofSize'] = int.parse(proofMatch.group(1)!);
    }

    return timings.isNotEmpty ? timings : null;
  }

  Future<void> _runSetup() async {
    setState(() {
      _isOperating = true;
      _currentPhase = OperationPhase.setup;
      _error = null;
      _setupResult = null;
      _setupTimeMs = null;
    });

    try {
      final documentsPath = await _getDocumentsPath();
      final result = _selectedCircuit == CircuitType.prepare
          ? await setupPrepareKeys(documentsPath: documentsPath)
          : await setupShowKeys(documentsPath: documentsPath);

      setState(() {
        _setupResult = result;
        _setupTimeMs = _parseTimeFromResult(result);
        _currentPhase = OperationPhase.complete;
      });
    } catch (e) {
      setState(() {
        _error = Exception('Setup failed: $e');
        _currentPhase = OperationPhase.idle;
      });
    } finally {
      setState(() {
        _isOperating = false;
      });
    }
  }

  Future<void> _runProve() async {
    setState(() {
      _isOperating = true;
      _currentPhase = OperationPhase.proving;
      _error = null;
      _proveResult = null;
      _proveTimeMs = null;
      _proveTimings = null;
    });

    try {
      final documentsPath = await _getDocumentsPath();
      final result = _selectedCircuit == CircuitType.prepare
          ? await provePrepareCircuit(documentsPath: documentsPath)
          : await proveShowCircuit(documentsPath: documentsPath);

      setState(() {
        _proveResult = result;
        _proveTimings = _parseDetailedTimings(result);
        _proveTimeMs = _proveTimings?['total'];
        _currentPhase = OperationPhase.verifying;
      });

      // Simulate verification phase (already done in Rust)
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _currentPhase = OperationPhase.complete;
      });
    } catch (e) {
      setState(() {
        _error = Exception('Proving failed: $e');
        _currentPhase = OperationPhase.idle;
      });
    } finally {
      setState(() {
        _isOperating = false;
      });
    }
  }

  Future<void> _runFullWorkflow() async {
    setState(() {
      _isOperating = true;
      _currentPhase = OperationPhase.setup;
      _error = null;
      _fullWorkflowResult = null;
      _setupTimeMs = null;
      _proveTimeMs = null;
    });

    try {
      final documentsPath = await _getDocumentsPath();

      // Update phase to proving
      setState(() {
        _currentPhase = OperationPhase.proving;
      });

      final result = _selectedCircuit == CircuitType.prepare
          ? await runPrepareCircuit(documentsPath: documentsPath)
          : await runShowCircuit(documentsPath: documentsPath);

      // Update phase to verifying
      setState(() {
        _currentPhase = OperationPhase.verifying;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _fullWorkflowResult = result;
        _fullWorkflowTimings = _parseDetailedTimings(result);
        _currentPhase = OperationPhase.complete;
      });
    } catch (e) {
      setState(() {
        _error = Exception('Full workflow failed: $e');
        _currentPhase = OperationPhase.idle;
      });
    } finally {
      setState(() {
        _isOperating = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _currentPhase = OperationPhase.idle;
      _setupResult = null;
      _proveResult = null;
      _fullWorkflowResult = null;
      _error = null;
      _setupTimeMs = null;
      _proveTimeMs = null;
      _proveTimings = null;
      _fullWorkflowTimings = null;
    });
  }

  Widget _buildPhaseIndicator(OperationPhase phase, String label, IconData icon) {
    final isActive = _currentPhase == phase;
    final isComplete = _currentPhase.index > phase.index && _currentPhase != OperationPhase.idle;

    Color color;
    if (isActive) {
      color = Colors.blue;
    } else if (isComplete) {
      color = Colors.green;
    } else {
      color = Colors.grey;
    }

    return Column(
      children: [
        Icon(
          isComplete ? Icons.check_circle : icon,
          color: color,
          size: 32,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseTracker() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildPhaseIndicator(OperationPhase.setup, 'Setup', Icons.settings),
            const Icon(Icons.arrow_forward, color: Colors.grey),
            _buildPhaseIndicator(OperationPhase.proving, 'Prove', Icons.calculate),
            const Icon(Icons.arrow_forward, color: Colors.grey),
            _buildPhaseIndicator(OperationPhase.verifying, 'Verify', Icons.verified),
            const Icon(Icons.arrow_forward, color: Colors.grey),
            _buildPhaseIndicator(OperationPhase.complete, 'Done', Icons.done_all),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback? onPressed,
    String? result,
    int? timeMs,
    Map<String, int>? detailedTimings,
    bool isPrimary = false,
  }) {
    return Card(
      elevation: isPrimary ? 4 : 2,
      color: isPrimary ? Colors.blue.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: isPrimary ? Colors.blue : Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isPrimary ? Colors.blue.shade900 : null,
                        ),
                      ),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isOperating ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPrimary ? Colors.blue : null,
                  foregroundColor: isPrimary ? Colors.white : null,
                ),
                child: Text(title),
              ),
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            result.split('|').first.trim(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detailedTimings != null) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 4),
                      Text(
                        'Timing Breakdown:',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (detailedTimings.containsKey('setup'))
                        _buildTimingRow('Setup', detailedTimings['setup']!),
                      if (detailedTimings.containsKey('prep'))
                        _buildTimingRow('Preparation', detailedTimings['prep']!),
                      if (detailedTimings.containsKey('prove'))
                        _buildTimingRow('Proving', detailedTimings['prove']!),
                      if (detailedTimings.containsKey('verify'))
                        _buildTimingRow('Verification', detailedTimings['verify']!),
                      if (detailedTimings.containsKey('proofSize')) ...[
                        const SizedBox(height: 4),
                        const Divider(),
                        _buildProofSizeRow(detailedTimings['proofSize']!),
                      ],
                      if (detailedTimings.containsKey('total')) ...[
                        const SizedBox(height: 4),
                        const Divider(),
                        _buildTimingRow(
                          'Total',
                          detailedTimings['total']!,
                          bold: true,
                        ),
                      ],
                    ] else if (timeMs != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Execution time: ${timeMs}ms (${(timeMs / 1000).toStringAsFixed(2)}s)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimingRow(String label, int ms, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${ms}ms (${(ms / 1000).toStringAsFixed(2)}s)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade900,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofSizeRow(int bytes) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Proof Size',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.normal,
            ),
          ),
          Text(
            '${(bytes / 1024).toStringAsFixed(2)} KB ($bytes bytes)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spartan2-Hyrax Circuits'),
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Circuit Selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Circuit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<CircuitType>(
                      segments: const [
                        ButtonSegment(
                          value: CircuitType.prepare,
                          label: Text('Prepare Circuit'),
                          icon: Icon(Icons.key),
                        ),
                        ButtonSegment(
                          value: CircuitType.show,
                          label: Text('Show Circuit'),
                          icon: Icon(Icons.visibility),
                        ),
                      ],
                      selected: {_selectedCircuit},
                      onSelectionChanged: _isOperating
                          ? null
                          : (Set<CircuitType> newSelection) {
                              setState(() {
                                _selectedCircuit = newSelection.first;
                                _reset();
                              });
                            },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Phase Tracker
            if (_currentPhase != OperationPhase.idle)
              _buildPhaseTracker(),

            const SizedBox(height: 16),

            // Progress Indicator
            if (_isOperating)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        _getCurrentPhaseText(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Error Display
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Error',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error.toString(),
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _reset,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Operation Cards
            _buildOperationCard(
              title: 'Generate Keys',
              description: 'Generate proving and verifying keys (one-time setup)',
              icon: Icons.vpn_key,
              onPressed: _runSetup,
              result: _setupResult,
              timeMs: _setupTimeMs,
            ),

            const SizedBox(height: 12),

            _buildOperationCard(
              title: 'Generate Proof',
              description: 'Generate proof using existing keys',
              icon: Icons.calculate,
              onPressed: _runProve,
              result: _proveResult,
              detailedTimings: _proveTimings,
            ),

            const SizedBox(height: 12),

            _buildOperationCard(
              title: 'Run Full Workflow',
              description: 'Execute complete setup + prove + verify pipeline',
              icon: Icons.play_circle,
              onPressed: _runFullWorkflow,
              result: _fullWorkflowResult,
              detailedTimings: _fullWorkflowTimings,
              isPrimary: true,
            ),

            const SizedBox(height: 16),

            // Reset Button
            if (_currentPhase != OperationPhase.idle && !_isOperating)
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getCurrentPhaseText() {
    switch (_currentPhase) {
      case OperationPhase.setup:
        return 'Setting up circuit keys...';
      case OperationPhase.proving:
        return 'Generating proof...';
      case OperationPhase.verifying:
        return 'Verifying proof...';
      case OperationPhase.complete:
        return 'Operation complete';
      default:
        return 'Processing...';
    }
  }
}
