import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

import 'package:namida/anki/class/anki_models.dart' as anki;
import 'package:namida/anki/controller/anki_controller.dart';
import 'package:namida/anki/controller/anki_droid_backend.dart';
import 'package:namida/base/setting_subpage_provider.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/controller/settings_search_controller.dart';
import 'package:namida/core/dimensions.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/translations/language.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/dialogs/edit_tags_dialog.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';
import 'package:namida/ui/widgets/settings/anki_advanced_dialog.dart';
import 'package:namida/ui/widgets/settings/anki_format_editor.dart';
import 'package:namida/ui/widgets/settings_card.dart';

/// Anki 制卡设置。
///
/// 信息架构照「后端 → 模板 → 行为 → 高级」分组：
/// - **后端**一张卡说清连什么，并给一个显眼的「获取」按钮。
/// - **模板**一张卡装下所有格式行 + 「添加卡片格式」行，点行进编辑器。
/// - **行为**全是开关与查重范围，放一张卡里。
/// - **高级**（词典回退、同步、卡片浏览器）收进子页，主页保持清爽。
class AnkiSettingsPage extends SettingSubpageProvider {
  const AnkiSettingsPage({super.key, super.initialItem});

  @override
  SettingSubpageEnum get settingPage => SettingSubpageEnum.anki;

  @override
  Map<SettingKeysBase, List<String>> buildLookupMap() => {
        _AnkiSettingKeys.backend: [lang.ankiBackendKind, lang.ankiBackendAnkiDroid, lang.ankiBackendAnkiConnect],
        _AnkiSettingKeys.fetch: [lang.ankiFetch],
        _AnkiSettingKeys.formats: [lang.ankiCardFormats, lang.ankiFormatAdd],
        _AnkiSettingKeys.duplicates: [lang.ankiDuplicates, lang.ankiAllowDuplicates, lang.ankiDuplicateScope],
        _AnkiSettingKeys.advanced: [lang.ankiAdvanced, lang.ankiSyncAfterAdding, lang.ankiSyncNow],
      };

  static AnkiController get _c => AnkiController.inst;

  static anki.AnkiSettings get _s => settings.anki.config.value;

  @override
  Widget build(BuildContext context) {
    return ObxO(
      rx: settings.anki.config,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _backendCard(),
          _formatsCard(context),

          _behaviorCard(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: CustomListTile(
              icon: Broken.filter,
              title: lang.ankiAdvanced,
              trailing: const Icon(Broken.arrow_right_3),
              onTap: () => NamidaNavigator.inst.navigateDialog(dialog: const AnkiAdvancedDialog()),
            ),
          ),
          kBottomPaddingWidget,
        ],
      ),
    );
  }

  // ==================================================================
  // backend
  // ==================================================================

  Widget _backendCard() {
    final isAnkiDroid = _s.backendKind == anki.AnkiBackendKind.ankiDroid;

    return SettingsCard(
      title: lang.ankiBackendKind,
      subtitle: isAnkiDroid ? lang.ankiBackendAnkiDroidSubtitle : lang.ankiBackendAnkiConnectSubtitle,
      icon: Broken.component,
      child: const SizedBox.shrink(),
      childRaw: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          getItemWrapper(
            key: _AnkiSettingKeys.backend,
            child: CustomListTile(
              icon: Broken.component,
              title: lang.ankiBackendKind,
              trailingText: isAnkiDroid ? lang.ankiBackendAnkiDroid : lang.ankiBackendAnkiConnect,
              onTap: _pickBackend,
            ),
          ),
          if (isAnkiDroid) ..._ankiDroidRows() else ..._ankiConnectRows(),
          getItemWrapper(key: _AnkiSettingKeys.fetch, child: _fetchRow()),
        ],
      ),
    );
  }

  /// 「获取」做成整行可点，右侧跟状态文字——比藏进一个 tile 更容易被看到。
  Widget _fetchRow() {
    return ObxO(
      rx: _c.isRefreshing,
      builder: (context, isRefreshing) {
        final failure = _c.lastFailureMessage.value;
        return CustomListTile(
          icon: Broken.refresh_circle,
          title: lang.ankiFetch,
          subtitle: failure ?? _fetchSubtitle(),
          trailingRaw: isRefreshing
              ? const SizedBox(
                  height: 18.0,
                  width: 18.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : NamidaButton(text: lang.ankiFetchNow, onTap: _refreshAndReport),
          onTap: isRefreshing ? null : _refreshAndReport,
        );
      },
    );
  }

  String _fetchSubtitle() {
    if (!_c.isBackendAvailable.value) return lang.ankiFetchSubtitleIdle;
    if (_s.availableDecks.isEmpty && _s.availableNoteTypes.isEmpty) return lang.ankiFetchSubtitleIdle;
    return lang.ankiFetchDone(decks: _s.availableDecks.length, noteTypes: _s.availableNoteTypes.length);
  }

  List<Widget> _ankiDroidRows() {
    return [
      ObxO(
        rx: _c.ankiDroidPermission,
        builder: (context, status) {
          final granted = status == AnkiDroidPermission.granted;
          final installed = status != AnkiDroidPermission.unavailable;
          return CustomListTile(
            icon: granted ? Broken.check : Broken.info_circle,
            passedColor: granted ? Colors.green : null,
            title: lang.ankiAnkiDroidPermission,
            subtitle: installed ? lang.ankiAnkiDroidPermissionSubtitle : lang.ankiAnkiDroidNotInstalled,
            trailingText: switch (status) {
              AnkiDroidPermission.granted => lang.ankiAnkiDroidPermissionGranted,
              AnkiDroidPermission.unavailable => lang.ankiAnkiDroidNotInstalled,
              AnkiDroidPermission.denied => lang.ankiAnkiDroidPermissionDenied,
              AnkiDroidPermission.notDetermined => lang.ankiAnkiDroidPermissionMissing,
            },
            // -- 还能弹系统对话框就直接申请；用户点过拒绝就只能去系统设置页。
            onTap: granted || !installed
                ? null
                : () => _c.requestAnkiDroidPermission(goToSettings: status == AnkiDroidPermission.denied),
          );
        },
      ),
      CustomListTile(
        icon: Broken.global,
        title: lang.ankiOpenAnkiDroid,
        trailing: const Icon(Broken.export_1, size: 18.0),
        onTap: _c.openAnkiDroid,
      ),
    ];
  }

  List<Widget> _ankiConnectRows() {
    final apiKey = settings.anki.ankiConnectApiKey.value;
    return [
      CustomListTile(
        icon: Broken.send,
        title: lang.ankiServerAddress,
        subtitle: lang.ankiServerAddressSubtitle(address: anki.kDefaultAnkiConnectUrl),
        trailingText: _s.ankiConnectUrl,
        onTap: () => _editText(
          title: lang.ankiServerAddress,
          initial: _s.ankiConnectUrl,
          hint: anki.kDefaultAnkiConnectUrl,
          onDone: (value) => _c.setAnkiConnect(url: value),
        ),
      ),
      CustomListTile(
        icon: Broken.key,
        title: lang.ankiApiKey,
        subtitle: lang.ankiApiKeySubtitle,
        trailingText: apiKey.isEmpty ? '' : '••••••••',
        onTap: () => _editText(
          title: lang.ankiApiKey,
          initial: apiKey,
          hint: '',
          onDone: (value) => _c.setAnkiConnect(apiKey: value),
        ),
      ),
    ];
  }

  void _pickBackend() {
    NamidaNavigator.inst.navigateDialog(
      dialog: AnkiValuePicker<anki.AnkiBackendKind>(
        title: lang.ankiBackendKind,
        values: anki.AnkiBackendKind.values,
        isSelected: (e) => e == _s.backendKind,
        titleOf: backendTitle,
        subtitleOf: backendSubtitle,
        onSelected: (kind) {
          _c.setBackendKind(kind);
          if (kind == anki.AnkiBackendKind.ankiDroid) {
            // -- 换后端后牌组缓存属于另一套收藏，清掉避免选到同名但不同的牌组。
            _c.updateSettings(
              (s) => s.copyWith(
                availableDecks: const [],
                availableNoteTypes: const [],
                cardFormats: s.cardFormats.map((f) => f.copyWith(clearDeck: true, clearNoteType: true)).toList(),
              ),
            );
          }
        },
      ),
    );
  }

  static String backendTitle(anki.AnkiBackendKind kind) => switch (kind) {
        anki.AnkiBackendKind.ankiDroid => lang.ankiBackendAnkiDroid,
        anki.AnkiBackendKind.ankiConnect => lang.ankiBackendAnkiConnect,
      };

  static String backendSubtitle(anki.AnkiBackendKind kind) => switch (kind) {
        anki.AnkiBackendKind.ankiDroid => lang.ankiBackendAnkiDroidSubtitle,
        anki.AnkiBackendKind.ankiConnect => lang.ankiBackendAnkiConnectSubtitle,
      };

  Future<void> _refreshAndReport() async {
    final ok = await _c.refresh();
    if (!ok) {
      snackyy(message: _c.lastFailureMessage.value ?? lang.ankiBackendKind, isError: true);
      return;
    }
    // -- 刷新会自动选牌组/卡片类型并套好字段模板，在这里告诉用户结果。
    final format = _c.defaultFormat;
    snackyy(
      message: [
        lang.ankiFetchDone(decks: _s.availableDecks.length, noteTypes: _s.availableNoteTypes.length),
        if (format != null) '${lang.ankiDeck}: ${format.selectedDeckName ?? '?'}',
        if (format?.selectedNoteTypeName != null) '${lang.ankiNoteType}: ${format?.selectedNoteTypeName}',
      ].join(' • '),
    );
  }

  // ANKI_SECTION_FORMATS

  // ==================================================================
  // card formats
  // ==================================================================

  Widget _formatsCard(BuildContext context) {
    final formats = _s.cardFormats;
    final canAdd = formats.length < anki.kMaxAnkiCardFormats;

    return SettingsCard(
      title: lang.ankiCardFormats,
      subtitle: lang.ankiCardFormatsSubtitle,
      icon: Broken.cards,
      child: const SizedBox.shrink(),
      childRaw: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...formats.map((f) => _formatRow(context, f)),
          CustomListTile(
            icon: canAdd ? Broken.add_circle : Broken.info_circle,
            title: lang.ankiFormatAdd,
            enabled: canAdd,
            onTap: canAdd ? () => _openEditor(_c.createFormat(name: lang.ankiFormatAdd).id) : null,
          ),
        ],
      ),
    );
  }

  Widget _formatRow(BuildContext context, anki.AnkiCardFormat format) {
    final filled = format.fieldMappings.values.where((e) => e.trim().isNotEmpty).length;
    final noteType = _s.availableNoteTypes.firstWhereOrNull((e) => e.id == format.selectedNoteTypeId);

    return CustomListTile(
      icon: format.isValid ? Broken.card_tick : Broken.card,
      title: format.name,
      subtitle: format.isValid
          ? '${format.selectedDeckName} · ${format.selectedNoteTypeName}'
          : lang.ankiFormatNotConfigured,
      trailingRaw: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (noteType != null && filled > 0)
            Text('$filled/${noteType.fields.length}', style: context.textTheme.displaySmall),
          SmallIconButton(
            icon: Broken.trash,
            onTap: _s.cardFormats.length > 1 ? () => _c.removeFormat(format.id) : null,
          ),
          const Icon(Broken.arrow_right_3),
        ],
      ),
      onTap: () => _openEditor(format.id),
    );
  }

  void _openEditor(String formatId) {
    NamidaNavigator.inst.navigateDialog(dialog: AnkiFormatEditor(formatId: formatId));
  }

  // ==================================================================
  // behavior
  // ==================================================================

  Widget _behaviorCard() {
    return SettingsCard(
      title: lang.ankiDuplicates,
      subtitle: lang.ankiDuplicatesSubtitle,
      icon: Broken.copy,
      child: const SizedBox.shrink(),
      childRaw: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          getItemWrapper(
            key: _AnkiSettingKeys.duplicates,
            child: CustomSwitchListTile(
              icon: Broken.copy,
              title: lang.ankiAllowDuplicates,
              value: _s.allowDupes,
              onChanged: (isTrue) => _c.setAllowDupes(!isTrue),
            ),
          ),
          CustomSwitchListTile(
            icon: Broken.layer,
            title: lang.ankiCheckAcrossNoteTypes,
            value: _s.checkDuplicatesAcrossAllModels,
            onChanged: (isTrue) => _c.setCheckDuplicatesAcrossAllModels(!isTrue),
          ),
          CustomListTile(
            icon: Broken.filter,
            title: lang.ankiDuplicateScope,
            trailingText: duplicateScopeText(_s.duplicateScope),
            onTap: _pickDuplicateScope,
          ),
        ],
      ),
    );
  }

  void _pickDuplicateScope() {
    NamidaNavigator.inst.navigateDialog(
      dialog: AnkiValuePicker<anki.AnkiDuplicateScope>(
        title: lang.ankiDuplicateScope,
        values: anki.AnkiDuplicateScope.values,
        isSelected: (e) => e == _s.duplicateScope,
        titleOf: duplicateScopeText,
        onSelected: _c.setDuplicateScope,
      ),
    );
  }

  static String duplicateScopeText(anki.AnkiDuplicateScope scope) => switch (scope) {
        anki.AnkiDuplicateScope.collection => lang.ankiDuplicateScopeCollection,
        anki.AnkiDuplicateScope.deck => lang.ankiDuplicateScopeDeck,
        anki.AnkiDuplicateScope.deckRoot => lang.ankiDuplicateScopeDeckRoot,
      };

  // ==================================================================
  // shared
  // ==================================================================

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

/// 设置项在设置搜索里的稳定 key。
enum _AnkiSettingKeys with SettingKeysBase {
  backend,
  fetch,
  formats,
  duplicates,
  advanced,
}
