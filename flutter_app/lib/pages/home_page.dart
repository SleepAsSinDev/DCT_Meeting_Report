import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';

import 'package:meeting_minutes_app/services/api.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api});
  final BackendApi api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool loading = false;
  double progress = 0.0;         // 0..100
  String partial = '';
  String status = 'พร้อม';
  String? transcript;
  String? report;
  String? pickedPath;

  // accumulate live transcript
  String liveText = '';
  String lastPiece = '';
  final ScrollController _transcriptScroll = ScrollController();

  void _scrollTranscriptToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptScroll.hasClients) {
        _transcriptScroll.animateTo(
          _transcriptScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final r = await widget.api.dio.get('/healthz');
        // ignore: avoid_print
        print('[HEALTH][client] /healthz -> ${r.statusCode} ${r.data}');
      } catch (e) {
        // ignore: avoid_print
        print('[HEALTH][client] failed: $e');
      }
    });
  }

  Future<void> pickAndTranscribe() async {
    setState(() {
      loading = true;
      status = 'เลือกไฟล์เสียง';
      progress = 0;
      partial = '';
      transcript = null;
      report = null;
      liveText = '';
      lastPiece = '';
    });

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.any,
    );

    if (result == null || (result.files.isEmpty)) {
      setState(() {
        loading = false;
        status = 'ยกเลิก';
      });
      return;
    }

    final path = result.files.single.path;
    if (path == null) {
      setState(() {
        loading = false;
        status = 'ไม่พบพาธไฟล์';
      });
      return;
    }
    pickedPath = path;

    setState(() {
      status = 'กำลังถอดเสียง (มีอัปเดตความคืบหน้า)';
    });

    try {
      await for (final ev in widget.api.transcribeStream(path,
          language: 'th', modelSize: 'large-v3', quality: 'accurate',
          preprocess: true, fastPreprocess: false)) {
        final event = (ev['event'] as String?) ?? '';

        if (event == 'progress') {
          final p = (ev['progress'] as num?)?.toDouble() ?? 0.0;
          final piece = ((ev['partial_text'] as String?) ?? '').trim();
          setState(() {
            progress = p.clamp(0, 100);
            partial = piece;
            if (piece.isNotEmpty && piece != lastPiece) {
              liveText += (liveText.isEmpty ? '' : ' ') + piece;
              lastPiece = piece;
            }
          });
          _scrollTranscriptToEnd();
        } else if (event == 'done') {
          final text = ((ev['text'] as String?) ?? '').trim();
          setState(() {
            transcript = text.isNotEmpty ? text : liveText;
            progress = 100;
            loading = false;
            status = 'ถอดเสียงเสร็จแล้ว';
          });
          _scrollTranscriptToEnd();
          break;
        }
      }
    } catch (e) {
      setState(() {
        loading = false;
        status = 'เกิดข้อผิดพลาด: $e';
      });
    }
  }

  Future<void> makeReport() async {
    final source = transcript ?? liveText;
    if (source.isEmpty) {
      setState(() {
        status = 'ยังไม่มีข้อความถอดเสียง';
      });
      return;
    }
    setState(() {
      loading = true;
      status = 'สรุปรายงาน...';
      report = null;
    });

    try {
      final md = await widget.api.summarize(source, sections: const [
        'สรุปประเด็นสำคัญ',
        'สิ่งที่ตัดสินใจ',
        'Action items (ผู้รับผิดชอบ/กำหนดเสร็จ)',
        'คำถามค้าง/ติดขัด',
      ]);
      setState(() {
        report = md;
        loading = false;
        status = 'เสร็จแล้ว';
      });
    } catch (e) {
      setState(() {
        loading = false;
        status = 'เกิดข้อผิดพลาด: $e';
      });
    }
  }

  @override
  void dispose() {
    _transcriptScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveOrFinal = transcript ?? (liveText.isNotEmpty ? liveText : (partial.isEmpty ? '-' : partial));
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting Minutes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: loading ? null : pickAndTranscribe,
                  child: const Text('เลือกไฟล์เสียง'),
                ),
                ElevatedButton(
                  onPressed: (loading || liveOrFinal.trim().isEmpty) ? null : makeReport,
                  child: const Text('สร้างรายงาน'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(status),
            if (loading) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (progress > 0 && progress < 100) ? (progress / 100.0) : null,
              ),
              const SizedBox(height: 6),
              Text('${progress.toStringAsFixed(1)}%'),
              if (partial.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  partial,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Transcript (สด)', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Divider(),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _transcriptScroll,
                                child: Text(liveOrFinal),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Report', style: TextStyle(fontWeight: FontWeight.bold)),
                            const Divider(),
                            Expanded(
                              child: report == null
                                  ? const Center(child: Text('-'))
                                  : Markdown(data: report!),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
