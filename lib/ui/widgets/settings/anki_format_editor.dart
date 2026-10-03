import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

import 'package:namida/anki/class/anki_field_templates.dart';
import 'package:namida/anki/class/anki_mining.dart';
import 'package:namida/anki/class/anki_models.dart' as anki;
import 'package:namida/anki/controller/anki_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/dictionary/class/word_lookup.dart';
import 'package:namida/ui/dialogs/edit_tags_dialog.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

/// 一套制卡模板的编辑器。
///
/// 结构：格式名 → 图标 / 牌组 / 卡片类型 → 标签 → 字段列表 → 预览。
///
/// 字段列表用**紧凑行**（字段名 + 当前模板，未映射显示「无」），
/// 而不是给每个字段摊一个输入框——Lapis 有 15 个字段，后者会把页面撑爆，
/// 而且一眼看不出整体映射对不对。点某行才展开该字段的编辑器。
class AnkiFormatEditor extends StatefulWidget {
  final String formatId;

  const AnkiFormatEditor({super.key, required this.formatId});

  @override
  State<AnkiFormatEditor> createState() => _AnkiFormatEditorState();
}

class _AnkiFormatEditorState extends State<AnkiFormatEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _tagsCtrl;

  /// 正在编辑模板的字段。null 表示没有字段在编辑。
  final _editingField = Rxn<String>();

  static AnkiController get _c => AnkiController.inst;

  static anki.AnkiSettings get _s => settings.anki.config.value;

  anki.AnkiCardFormat? get _format => _s.cardFormats.firstWhereOrNull((e) => e.id == widget.formatId);

  anki.AnkiNoteType? get _noteType {
    final id = _format?.selectedNoteTypeId;
    if (id == null) return null;
    return _s.availableNoteTypes.firstWhereOrNull((e) => e.id == id);
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _format?.name ?? '');
    _tagsCtrl = TextEditingController(text: _format?.tags ?? '');
  }

  /// 名称可能来自别处改动（复制/删除模板后弹窗复用），这里把控制器拉回最新值。
  /// 只在文案真的不一致时写回，否则会打断用户正在输入的字。
  void _syncNameFromSettings(anki.AnkiCardFormat format) {
    final stored = format.name;
    if (stored == _nameCtrl.text) return;
    if (_nameCtrl.selection.isCollapsed && stored.startsWith(_nameCtrl.text)) {
      // -- 用户正在往后打字，保留他们的光标。
      return;
    }
    _nameCtrl.value = TextEditingValue(
      text: stored,
      selection: TextSelection.collapsed(offset: stored.length),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tagsCtrl.dispose();
    _editingField.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: settings.anki.config,
      builder: (context, _) {
        final format = _format;
        if (format == null) return const SizedBox.shrink();
        _syncNameFromSettings(format);

        return CustomBlurryDialog(
          // -- 标题就是格式名，改名即时反映在标题上。
          title: format.name.trim().isEmpty ? lang.ankiCardFormats : format.name,
          normalTitleStyle: true,
          trailingWidgets: [
            SmallIconButton(icon: Broken.copy, onTap: _duplicate),
            SmallIconButton(icon: Broken.trash, onTap: _remove),
          ],
          actions: const [DoneButton()],
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identityCard(format),
                const SizedBox(height: 10.0),
                CustomTagTextField(
                  controller: _tagsCtrl,
                  hintText: anki.kDefaultAnkiTag,
                  labelText: lang.ankiTags,
                  onChanged: (value) => _c.setFormatTags(widget.formatId, value),
                ),
                const SizedBox(height: 12.0),
                ..._fieldSection(context, format),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // identity: name / icon / deck / note type
  // ------------------------------------------------------------------

  Widget _identityCard(anki.AnkiCardFormat format) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomTagTextField(
          controller: _nameCtrl,
          hintText: lang.ankiFormatName,
          labelText: lang.ankiFormatName,
          onChanged: (value) => _c.renameFormat(widget.formatId, value),
        ),
        const SizedBox(height: 6.0),
        ListTileWithCheckMark(
          icon: Broken.diamonds,
          title: lang.ankiFormatIcon,
          onTap: () => _pickIcon(format),
        ),
        ListTileWithCheckMark(
          icon: Broken.cards,
          title: lang.ankiDeck,
          subtitle: format.selectedDeckName ?? lang.ankiUnset,
          onTap: () => _pickDeck(format),
        ),
        ListTileWithCheckMark(
          icon: Broken.note_text,
          title: lang.ankiNoteType,
          subtitle: format.selectedNoteTypeName ?? lang.ankiUnset,
          onTap: () => _pickNoteType(format),
        ),
      ],
    );
  }

  void _pickIcon(anki.AnkiCardFormat format) {
    NamidaNavigator.inst.navigateDialog(
      dialog: CustomBlurryDialog(
        title: lang.ankiFormatIcon,
        normalTitleStyle: true,
        actions: const [DoneButton()],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: anki.AnkiFormatIcon.values.map((icon) {
            return ListTileWithCheckMark(
              title: icon.storageValue,
              active: format.icon == icon,
              icon: Broken.check,
              onTap: () {
                _c.updateSettings((s) => s.updateCardFormat(widget.formatId, (f) => f.copyWith(icon: icon)));
                NamidaNavigator.inst.closeDialog();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _pickDeck(anki.AnkiCardFormat format) {
    NamidaNavigator.inst.navigateDialog(
      dialog: AnkiValuePicker<anki.AnkiDeck>(
        title: lang.ankiDeck,
        values: _s.availableDecks,
        isSelected: (e) => e.id == format.selectedDeckId,
        titleOf: (e) => e.name,
        onSelected: (deck) => _c.setFormatTarget(widget.formatId, deck: deck),
      ),
    );
  }

  void _pickNoteType(anki.AnkiCardFormat format) {
    NamidaNavigator.inst.navigateDialog(
      dialog: AnkiValuePicker<anki.AnkiNoteType>(
        title: lang.ankiNoteType,
        values: _s.availableNoteTypes,
        isSelected: (e) => e.id == format.selectedNoteTypeId,
        titleOf: (e) => e.name,
        subtitleOf: (e) => e.fields.join(' / '),
        // -- 换卡片类型后字段名全变了，旧的映射已经没有意义。
        onSelected: (type) => _c.setFormatTarget(
          widget.formatId,
          noteType: type,
          clearFieldMappings: true,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // fields
  // ------------------------------------------------------------------

  List<Widget> _fieldSection(BuildContext context, anki.AnkiCardFormat format) {
    final noteType = _noteType;
    if (noteType == null) {
      return [_sectionLabel(lang.ankiFieldTemplates, lang.ankiPreviewEmpty)];
    }

    return [
      _sectionLabel(lang.ankiFieldTemplates, lang.ankiFieldTemplatesSubtitle),
      if (AnkiFieldTemplates.matches(noteType)) ...[
        _autoFilledHint(format, noteType),
        const SizedBox(height: 4.0),
      ],
      ...noteType.fields.map((field) => _fieldRow(context, format, noteType, field)),
      const SizedBox(height: 8.0),
      ..._previewSection(context, format, noteType),
    ];
  }

  /// 内置模板已经填好时给个提示，并提供「清空」退路——
  /// 用户看到满屏模板却不知道是自动来的，最怕的就是删不掉。
  Widget _autoFilledHint(anki.AnkiCardFormat format, anki.AnkiNoteType noteType) {
    final defaults = AnkiFieldTemplates.defaultMappings(noteType);
    final usingDefaults = defaults.isNotEmpty &&
        defaults.entries.every((entry) => format.fieldMappings[entry.key]?.trim() == entry.value);
    if (!usingDefaults) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(Broken.tick_circle, size: 16.0, color: context.theme.colorScheme.primary),
          const SizedBox(width: 6.0),
          Expanded(child: Text(lang.ankiFieldsAutoFilled, style: context.textTheme.displaySmall)),
          NamidaTextButton(
            text: lang.ankiFieldsClearAll,
            onTap: () => _c.setFormatTarget(widget.formatId, clearFieldMappings: true),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(
    BuildContext context,
    anki.AnkiCardFormat format,
    anki.AnkiNoteType noteType,
    String field,
  ) {
    final template = format.fieldMappings[field]?.trim() ?? '';
    final isEditing = _editingField.value == field;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTileWithCheckMark(
          title: field,
          subtitle: template.isEmpty ? lang.ankiFieldUnmapped : template,
          active: template.isNotEmpty,
          icon: Broken.filter,
          onTap: () => _editingField.value = isEditing ? null : field,
        ),
        if (isEditing) _fieldEditor(context, format, noteType, field),
      ],
    );
  }

  Widget _fieldEditor(
    BuildContext context,
    anki.AnkiCardFormat format,
    anki.AnkiNoteType noteType,
    String field,
  ) {
    final controller = TextEditingController(text: format.fieldMappings[field] ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomTagTextField(
            controller: controller,
            hintText: field,
            labelText: field,
            maxLines: 3,
            onChanged: (value) => _c.setFieldMapping(widget.formatId, field, value),
          ),
          const SizedBox(height: 6.0),
          Text(lang.ankiAvailableFields, style: context.textTheme.displaySmall),
          const SizedBox(height: 4.0),
          _handlebarChips(format, field, controller),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SmallIconButton(
              icon: Broken.check,
              onTap: () => _editingField.value = null,
            ),
          ),
        ],
      ),
    );
  }

  /// 只展示这套模板真正用到的占位符，没配过时给几个常见的。
  Widget _handlebarChips(anki.AnkiCardFormat format, String field, TextEditingController controller) {
    final all = AnkiHandlebarRenderer.handlebarDescriptions.keys.toList();
    final used = all.where(format.references).toList();
    final shown = used.isNotEmpty ? used : all.take(6).toList();

    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children: shown.map((handlebar) {
        return Tooltip(
          message: AnkiHandlebarRenderer.handlebarDescriptions[handlebar] ?? '',
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text(handlebar, style: const TextStyle(fontSize: 11.0)),
            onPressed: () {
              final current = controller.text;
              // -- 同一个占位符重复插进去没意义。
              if (current.contains(handlebar)) return;
              final updated = current.isEmpty ? handlebar : '$current$handlebar';
              controller.text = updated;
              controller.selection = TextSelection.collapsed(offset: updated.length);
              _c.setFieldMapping(widget.formatId, field, updated);
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(subtitle, style: context.textTheme.displaySmall),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // preview
  // ------------------------------------------------------------------

  List<Widget> _previewSection(BuildContext context, anki.AnkiCardFormat format, anki.AnkiNoteType noteType) {
    final rendered = AnkiFieldRenderer.renderFields(
      noteType: noteType,
      fieldMappings: format.fieldMappings,
      lookup: AnkiPreviewData.demoLookup,
      context: const AnkiMiningContext(documentTitle: '_sample_'),
    );

    final filled = rendered.fields.entries.where((e) => e.value.trim().isNotEmpty).toList();
    if (filled.isEmpty) return const [];

    return [
      _sectionLabel(lang.ankiPreview, lang.ankiPreviewSubtitle),
      ...filled.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 92.0, child: Text(entry.key, style: context.textTheme.displaySmall)),
              Expanded(child: Text(entry.value, style: context.textTheme.displayMedium)),
            ],
          ),
        );
      }),
    ];
  }

  // ------------------------------------------------------------------
  // actions
  // ------------------------------------------------------------------

  void _duplicate() {
    _c.duplicateFormat(widget.formatId);
    NamidaNavigator.inst.closeDialog();
  }

  void _remove() {
    if (_s.cardFormats.length <= 1) return;
    _c.removeFormat(widget.formatId);
    NamidaNavigator.inst.closeDialog();
  }
}

/// 通用单选弹窗（牌组 / 卡片类型 / 查重范围…）。
class AnkiValuePicker<T> extends StatelessWidget {
  final String title;
  final List<T> values;
  final bool Function(T) isSelected;
  final String Function(T) titleOf;
  final String Function(T)? subtitleOf;
  final void Function(T) onSelected;
  final String emptyText;

  const AnkiValuePicker({
    super.key,
    required this.title,
    required this.values,
    required this.isSelected,
    required this.titleOf,
    this.subtitleOf,
    required this.onSelected,
    this.emptyText = '',
  });

  @override
  Widget build(BuildContext context) {
    return CustomBlurryDialog(
      title: title,
      normalTitleStyle: true,
      actions: const [DoneButton()],
      child: values.isEmpty
          ? Center(child: Text(emptyText.isEmpty ? lang.ankiRefresh : emptyText))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: values.map((value) {
                return ListTileWithCheckMark(
                  title: titleOf(value),
                  subtitle: subtitleOf?.call(value) ?? '',
                  active: isSelected(value),
                  icon: Broken.check,
                  onTap: () {
                    onSelected(value);
                    NamidaNavigator.inst.closeDialog();
                  },
                );
              }).toList(),
            ),
    );
  }
}

/// 设置页预览用的样例查词结果。
class AnkiPreviewData {
  const AnkiPreviewData._();

  static final demoLookup = WordLookupResult(
    expression: '言葉',
    reading: 'ことば',
    matched: '言葉',
    sentence: '彼の言葉の意味を調べる。',
    sentenceOffset: 2,
    singleGlossaries: const {
      'JMdict': '<b>言葉</b><br><i>(1) word, phrase, expression</i>',
    },
    glossary: '<li data-dictionary="JMdict"><i>(JMdict)</i> word, phrase, expression</li>',
    glossaryFirst: '<b>言葉</b><br><i>(1) word, phrase, expression</i>',
    selectedDictionary: 'JMdict',
  );
}
