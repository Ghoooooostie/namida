library;

import 'package:namida/anki/class/anki_mining.dart';
import 'package:namida/anki/class/anki_models.dart' as anki;

/// 常见卡片类型的内置字段模板。
///
/// 只覆盖市面上的mining 卡片类型（Lapis / Kiku / Senren），因为这些类型的字段名是**固定的**，
/// 可以直接对上；用户自建类型字段名千奇百怪，猜反而会填错，不如留空让他自己写。
/// 模板里只用 [AnkiHandlebarRenderer] 真正实现了的占位符。
class AnkiFieldTemplates {
  const AnkiFieldTemplates._();

  /// Lapis 与 Kiku 的字段名完全一样，共用一份。
  static const Map<String, String> _lapis = {
    'Expression': '{expression}',
    'ExpressionFurigana': '{furigana-plain}',
    'ExpressionReading': '{reading}',
    'ExpressionAudio': '{audio}',
    'SelectionText': '{popup-selection-text}',
    'MainDefinition': '{glossary-first}',
    'Sentence': '{sentence}',
    'SentenceAudio': '{audio-clip}',
    'Picture': '{book-cover}',
    'Glossary': '{glossary}',
    'Frequency': '{frequencies}',
    'FreqSort': '{frequency-harmonic-rank}',
    'MiscInfo': '{document-title}',
  };

  static const Map<String, String> _senren = {
    'word': '{expression}',
    'reading': '{reading}',
    'sentence': '{cloze-prefix}<b>{cloze-body}</b>{cloze-suffix}',
    'selectionText': '{popup-selection-text}',
    'definition': '{glossary-first}',
    'wordAudio': '{audio}',
    'sentenceAudio': '{audio-clip}',
    'picture': '{book-cover}',
    'glossary': '{glossary}',
    'frequencies': '{frequencies}',
    'freqSort': '{frequency-harmonic-rank}',
    'miscInfo': '{document-title}',
  };

  /// 按卡片类型名索引。键全小写，匹配时忽略大小写与首尾空格。
  static final Map<String, Map<String, String>> _templates = {
    'lapis': _lapis,
    'kiku': _lapis,
    'senren': _senren,
  };

  /// 这套卡片类型是否有内置模板。
  static bool matches(anki.AnkiNoteType noteType) => _lookup(noteType) != null;

  /// 内置模板里该卡片类型**实际拥有**的那些字段 -> 模板。
  /// 卡片类型被用户改过字段（多删了几个）时，只给还留着的字段填。
  static Map<String, String> defaultMappings(anki.AnkiNoteType noteType) {
    final defaults = _lookup(noteType);
    if (defaults == null) return const {};
    return {
      for (final field in noteType.fields)
        if (defaults[field] != null) field: defaults[field]!,
    };
  }

  /// 选中卡片类型时套用内置模板。
  ///
  /// 规则和 Hoshi 一致：**一个字段都还没映射过**才套用。
  /// 用户已经手动配过的模板绝不覆盖 —— 那是最贵的东西，不能因为换个类型就没了。
  static Map<String, String> applyDefaultsIfUnmapped(
    anki.AnkiNoteType noteType,
    Map<String, String> currentMappings,
  ) {
    if (!matches(noteType)) return currentMappings;
    if (noteType.fields.any((field) => currentMappings[field] != null)) return currentMappings;
    return defaultMappings(noteType);
  }

  static Map<String, String>? _lookup(anki.AnkiNoteType noteType) {
    return _templates[noteType.name.trim().toLowerCase()];
  }
}
