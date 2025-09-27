import 'package:flutter/material.dart';

import 'package:meeting_minutes_app/services/transcription_config.dart';

class TranscriptionConfigDialog extends StatefulWidget {
  const TranscriptionConfigDialog({super.key, required this.initialConfig});

  final TranscriptionConfig initialConfig;

  @override
  State<TranscriptionConfigDialog> createState() =>
      _TranscriptionConfigDialogState();
}

class _TranscriptionConfigDialogState
    extends State<TranscriptionConfigDialog> {
  static const _modelPresets = <String>[
    'tiny',
    'base',
    'small',
    'medium',
    'large-v2',
    'large-v3',
  ];

  late String _modelSelection;
  late String _quality;
  late bool _preprocess;
  late bool _fastPreprocess;
  late TextEditingController _customModelController;
  late TextEditingController _languageController;
  late TextEditingController _initialPromptController;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _quality = initial.quality;
    _preprocess = initial.preprocess;
    _fastPreprocess = initial.fastPreprocess;
    final isPreset = _modelPresets.contains(initial.modelSize);
    _modelSelection = isPreset ? initial.modelSize : 'custom';
    _customModelController = TextEditingController(
        text: isPreset ? '' : initial.modelSize);
    _languageController =
        TextEditingController(text: initial.language.trim());
    _initialPromptController =
        TextEditingController(text: initial.initialPrompt.trim());
  }

  @override
  void dispose() {
    _customModelController.dispose();
    _languageController.dispose();
    _initialPromptController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final language = _languageController.text.trim();
    final initialPrompt = _initialPromptController.text.trim();
    final selectedModel = _modelSelection == 'custom'
        ? _customModelController.text.trim()
        : _modelSelection;
    final config = widget.initialConfig.copyWith(
      modelSize: selectedModel,
      language: language,
      quality: _quality,
      preprocess: _preprocess,
      fastPreprocess: _preprocess ? _fastPreprocess : false,
      initialPrompt: initialPrompt,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ปรับแต่งการถอดเสียง'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'โมเดล (เลือก presets หรือ Custom)',
                ),
                value: _modelSelection,
                items: [
                  ..._modelPresets.map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(m),
                    ),
                  ),
                  const DropdownMenuItem(
                    value: 'custom',
                    child: Text('Custom path/name'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _modelSelection = value;
                    if (value != 'custom') {
                      _customModelController.clear();
                    }
                  });
                },
              ),
              if (_modelSelection == 'custom')
                TextFormField(
                  controller: _customModelController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อโมเดลหรือ path เต็ม',
                    hintText: 'เช่น large-v3 หรือ ~/models/faster-whisper',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกชื่อโมเดลหรือ path';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _languageController,
                decoration: const InputDecoration(
                  labelText: 'ภาษา (เช่น th, en หรือ auto)',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'กรุณากรอกภาษา';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'โหมดคุณภาพ'),
                value: _quality,
                items: const [
                  DropdownMenuItem(value: 'accurate', child: Text('accurate')),
                  DropdownMenuItem(value: 'balanced', child: Text('balanced')),
                  DropdownMenuItem(value: 'fast', child: Text('fast')),
                  DropdownMenuItem(value: 'hyperfast', child: Text('hyperfast')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _quality = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('เปิดการ preprocess ด้วย ffmpeg'),
                subtitle: const Text(
                    'ช่วยให้เสียงมีความคงที่มากขึ้น เหมาะกับงานสำคัญ'),
                value: _preprocess,
                onChanged: (value) {
                  setState(() {
                    _preprocess = value;
                    if (!value) {
                      _fastPreprocess = false;
                    }
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('โหมด preprocess แบบรวดเร็ว'),
                subtitle: const Text('ลดเวลาประมวลผล เหมาะกับการทดลองเบื้องต้น'),
                value: _fastPreprocess,
                onChanged: _preprocess
                    ? (value) {
                        setState(() {
                          _fastPreprocess = value;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _initialPromptController,
                decoration: const InputDecoration(
                  labelText: 'Initial prompt (ไม่บังคับ)',
                  hintText: 'ใส่บริบทเพิ่มเติม เช่น ชื่อบริษัทหรือคำเฉพาะ',
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save),
          label: const Text('บันทึกและรีสตาร์ท'),
        ),
      ],
    );
  }
}
