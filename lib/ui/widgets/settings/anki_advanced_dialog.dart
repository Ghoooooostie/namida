import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

import 'package:namida/anki/class/anki_models.dart' as anki;
import 'package:namida/anki/controller/anki_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/dialogs/edit_tags_dialog.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// 「高级」子页。
///
/// 收拢低频设置：词典回退、默认标签、同步、卡片浏览器。
/// 主页只留下每天真会用到的三组（后端 / 模板 / 查重）。
class AnkiAdvancedDialog extends StatelessWidget {
  const AnkiAdvancedDialog({super.key});

  static AnkiController get _c => AnkiController.inst;

  static anki.AnkiSettings get _s => settings.anki.config.value;

  /// 全部模板统一使用的标签串。
  String get _defaultTags => _s.cardFormats.firstOrNull?.tags ?? anki.kDefaultAnkiTag;

  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: settings.anki.config,
      builder: (context, _) => CustomBlurryDialog(
        title: lang.ankiAdvanced,
        normalTitleStyle: true,
        actions: const [DoneButton()],
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomListTile(
                icon: Broken.note_text,
                title: lang.ankiGlossaryFallback,
                subtitle: lang.ankiGlossaryFallbackSubtitle(example: '{glossary-first}'),
                trailingText: _s.selectedGlossaryFallback.isEmpty ? '—' : _s.selectedGlossaryFallback,
                onTap: () => _editText(
                  title: lang.ankiGlossaryFallback,
                  initial: _s.selectedGlossaryFallback,
                  hint: '{glossary-first}',
                  onDone: _c.setSelectedGlossaryFallback,
                ),
              ),
              CustomListTile(
                icon: Broken.book,
                title: lang.ankiDefaultTag,
                subtitle: lang.ankiDefaultTagSubtitle,
                trailingText: _defaultTags,
                onTap: () => _editText(
                  title: lang.ankiDefaultTag,
                  initial: _defaultTags,
                  hint: anki.kDefaultAnkiTag,
                  onDone: _setDefaultTags,
                ),
              ),
              CustomSwitchListTile(
                icon: Broken.refresh_circle,
                title: lang.ankiSyncAfterAdding,
                subtitle: lang.ankiSyncAfterAddingSubtitle,
                value: _s.forceSync,
                onChanged: (isTrue) => _c.setForceSync(!isTrue),
              ),
              CustomListTile(
                icon: Broken.cloud,
                title: lang.ankiSyncNow,
                onTap: () async {
                  final ok = await _c.sync();
                  snackyy(message: ok ? lang.done : lang.ankiSyncFailed, isError: !ok);
                },
              ),
              CustomListTile(
                icon: Broken.eye,
                title: lang.ankiOpenCardBrowser,
                subtitle: lang.ankiOpenCardBrowserSubtitle,
                onTap: () => _c.openNotes(key: AnkiLastLookup.term.value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setDefaultTags(String value) {
    final tags = value.trim().isEmpty ? anki.kDefaultAnkiTag : value.trim();
    _c.updateSettings(
      (s) => s.copyWith(
        cardFormats: s.cardFormats.map((f) => f.copyWith(tags: tags)).toList(),
      ),
    );
  }

  void _editText({
    required String title,
    required String initial,
    required String hint,
    required void Function(String) onDone,
  }) {
    final controller = TextEditingController(text: initial);
    NamidaNavigator.inst.navigateDialog(
      dialog: CustomBlurryDialog(
        title: title,
        normalTitleStyle: true,
        actions: [
          const CancelButton(),
          NamidaButton(
            text: lang.save,
            onTap: () {
              onDone(controller.text.trim());
              NamidaNavigator.inst.closeDialog();
            },
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: CustomTagTextField(controller: controller, hintText: hint, labelText: title),
        ),
      ),
    );
  }
}
