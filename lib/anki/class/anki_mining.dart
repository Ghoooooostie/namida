import 'package:namida/anki/class/anki_models.dart';
import 'package:namida/dictionary/class/word_lookup.dart';

/// 制卡上下文：描述「这张卡来自哪里」。
///
/// 与 [WordLookupResult] 的区别：载荷是**查词给的**，上下文是**来源侧给的**。
/// 例如听书转录还没接上时，例句音频片段和截图由播放页准备好后放进这里；
/// 查词结果只需要给词条和释义。
class AnkiMiningContext {
  /// 完整例句。为空时回落到 [WordLookupResult.sentence]。
  final String sentence;

  /// [matched] 在 [sentence] 里的偏移，用于 `{cloze-prefix}` / `{cloze-body}` / `{cloze-suffix}`。
  final int? sentenceOffset;

  /// 来源标题。听书是书名，视频/音频是曲目名。
  final String documentTitle;

  /// 封面图片的本地绝对路径，对应 `{book-cover}`。
  final String? coverPath;

  /// 例句音频片段的本地绝对路径，对应 `{audio-clip}`。
  final String? audioClipPath;

  /// 例句截图的本地绝对路径，对应 `{sentence-image}`。
  final String? sentenceImagePath;

  /// 整条音频的本地绝对路径，用于按需二次裁剪。
  final String? sourceAudioPath;

  /// 音频片段在 [sourceAudioPath] 中的起点（毫秒）。
  final int? audioClipStartMS;

  const AnkiMiningContext({
    this.sentence = '',
    this.sentenceOffset,
    this.documentTitle = '',
    this.coverPath,
    this.audioClipPath,
    this.sentenceImagePath,
    this.sourceAudioPath,
    this.audioClipStartMS,
  });

  /// 媒体入库后用真实引用覆盖路径。
  AnkiMiningContext copyWith({
    String? sentence,
    int? sentenceOffset,
    String? documentTitle,
    String? coverPath,
    String? audioClipPath,
    String? sentenceImagePath,
    String? sourceAudioPath,
    int? audioClipStartMS,
  }) =>
      AnkiMiningContext(
        sentence: sentence ?? this.sentence,
        sentenceOffset: sentenceOffset ?? this.sentenceOffset,
        documentTitle: documentTitle ?? this.documentTitle,
        coverPath: coverPath ?? this.coverPath,
        audioClipPath: audioClipPath ?? this.audioClipPath,
        sentenceImagePath: sentenceImagePath ?? this.sentenceImagePath,
        sourceAudioPath: sourceAudioPath ?? this.sourceAudioPath,
        audioClipStartMS: audioClipStartMS ?? this.audioClipStartMS,
      );
}

/// 一张待写入 Anki 的卡片。字段值已渲染成最终 HTML。
class AnkiCardDraft {
  final AnkiDeck deck;
  final AnkiNoteType noteType;

  /// 字段名 -> 已渲染的 HTML。
  final Map<String, String> fields;

  final Set<String> tags;

  /// 查重用的键，通常是首字段（Front）。
  final String duplicateKey;

  const AnkiCardDraft({
    required this.deck,
    required this.noteType,
    required this.fields,
    this.tags = const {},
    this.duplicateKey = '',
  });
}

/// 制卡结果。
enum AnkiAddResult {
  /// 写入成功。
  success,

  /// 已经是重复卡，且不允许重复。
  duplicate,

  /// 模板没配好（缺牌组 / 缺卡片类型 / 字段全空）。
  invalidFormat,

  /// 后端不可用（AnkiDroid 没装、AnkiConnect 连不上）。
  backendUnavailable,

  /// 后端返回了错误。
  failed,
}

/// 可插入 Anki 字段的媒体。
class AnkiMediaDraft {
  /// 本地绝对路径。
  final String path;

  /// 期望的文件名（不含目录），Anki 会据此决定 `[sound:x]` / `<img src="x">`。
  final String preferredName;

  final String mimeType;

  const AnkiMediaDraft({required this.path, required this.preferredName, required this.mimeType});

  bool get isAudio => mimeType.startsWith('audio/');
  bool get isImage => mimeType.startsWith('image/');
}

/// 一套字段模板渲染出来的字段值。
class AnkiRenderedFields {
  /// 字段名 -> HTML。
  final Map<String, String> fields;

  /// 渲染过程中发现缺失的媒体路径（本地文件不存在）。
  final List<String> missingMediaPaths;

  const AnkiRenderedFields({required this.fields, this.missingMediaPaths = const []});
}

/// 把 handlebars 模板渲染成 Anki 字段值。
///
/// 支持的 handlebars 见 [AnkiHandlebarRenderer.handledHandlebars]。
/// 未知 handlebar 一律渲染成空串，和 Hoshi 行为一致（避免用户模板里打错字就把整张卡写坏）。
class AnkiHandlebarRenderer {
  const AnkiHandlebarRenderer._();

  static final RegExp _handlebarRegex = RegExp(r'\{[^}]*\}');

  /// `<li data-dictionary="XXX"><i>YYY, XXX)</i> ...` 这种带词典名的释义头。
  static final RegExp _glossaryHeaderRegex = RegExp(r'(<li data-dictionary="[^"]*">)<i>[^<]*</i> ');

  /// 需要把词典名从释义里摘掉时用。
  static final RegExp _dictionaryLabelRegex = RegExp(r'<li data-dictionary="([^"]+)"><i>([^<]*)</i> ');

  static final RegExp _tagWhitespaceRegex = RegExp(r'[\s　]+');

  /// 标签值里不允许空格。
  static final Set<String> _selectedGlossaryHandlebars = {
    '{selected-glossary}',
    '{selected-glossary-brief}',
    '{selected-glossary-no-dictionary}',
    '{selected-glossary-fallback}',
    '{selected-glossary-brief-fallback}',
    '{selected-glossary-no-dictionary-fallback}',
  };

  /// 设置界面下拉里展示的 handlebar 说明。
  static const Map<String, String> handlebarDescriptions = {
    '{expression}': '词条本体',
    '{reading}': '读音 / 音标',
    '{furigana-plain}': '纯文本读音',
    '{glossary}': '全部释义',
    '{glossary-brief}': '全部释义（去掉词典名）',
    '{glossary-no-dictionary}': '全部释义（去掉词典名后缀）',
    '{glossary-first}': '第一条释义',
    '{glossary-first-brief}': '第一条释义（去掉词典名）',
    '{monolingual-definition}': '第一条同语词典释义',
    '{bilingual-definition}': '第一条双语词典释义',
    '{monolingual-definition-fallback}': '同语优先，缺失时回退双语',
    '{bilingual-definition-fallback}': '双语优先，缺失时回退同语',
    '{selected-glossary}': '查词时选中的那个词典的释义',
    '{selected-glossary-fallback}': '同上，为空时回退第一条释义',
    '{single-glossary-词典名}': '指定词典的释义',
    '{sentence}': '例句（命中词加粗）',
    '{sentence-translation}': '例句翻译',
    '{sentence-image}': '例句截图文件名',
    '{audio}': '单词发音文件名',
    '{audio-clip}': '例句音频片段文件名',
    '{book-cover}': '封面图片文件名',
    '{document-title}': '来源标题（书名 / 曲目名）',
    '{cloze-prefix}': '例句中命中词之前的部分',
    '{cloze-body}': '例句中命中的词',
    '{cloze-suffix}': '例句中命中词之后的部分',
    '{frequencies}': '词频 HTML',
    '{frequency-harmonic-rank}': '词频调和排名',
    '{popup-selection-text}': '查词弹窗里选中的文本',
  };

  static Set<String> get handledHandlebars => handlebarDescriptions.keys.toSet();

  /// 渲染一个字段模板。
  static String render(
    String template, {
    required WordLookupResult lookup,
    required AnkiMiningContext context,
    String selectedGlossaryFallback = '',
    List<WordLookupGlossary> termGlossaries = const [],
  }) {
    return template.replaceAllMapped(_handlebarRegex, (match) {
      return _resolve(
        match.group(0)!,
        lookup: lookup,
        context: context,
        selectedGlossaryFallback: selectedGlossaryFallback,
        termGlossaries: termGlossaries,
      );
    });
  }

  /// 渲染标签模板：先按普通字段渲染，再把空白折叠掉，标签本身不允许含空格。
  static String renderTag(
    String template, {
    required WordLookupResult lookup,
    required AnkiMiningContext context,
    String selectedGlossaryFallback = '',
    List<WordLookupGlossary> termGlossaries = const [],
  }) {
    final rendered = render(
      template,
      lookup: lookup,
      context: context,
      selectedGlossaryFallback: selectedGlossaryFallback,
      termGlossaries: termGlossaries,
    );
    return rendered.split(_tagWhitespaceRegex).where((e) => e.isNotEmpty).join('_');
  }

  static String _resolve(
    String handlebar, {
    required WordLookupResult lookup,
    required AnkiMiningContext context,
    required String selectedGlossaryFallback,
    required List<WordLookupGlossary> termGlossaries,
  }) {
    // -- {single-glossary-XXX} / {single-glossary-XXX-brief} / {single-glossary-XXX-no-dictionary}
    if (handlebar.startsWith('{single-glossary-')) {
      final dictionary = handlebar.substring('{single-glossary-'.length, handlebar.length - 1);
      if (dictionary.endsWith('-no-dictionary')) {
        final base = dictionary.substring(0, dictionary.length - '-no-dictionary'.length);
        return _stripDictionaryName(_singleGlossary(lookup, base));
      }
      if (dictionary.endsWith('-brief')) {
        final base = dictionary.substring(0, dictionary.length - '-brief'.length);
        return _stripGlossaryHeaders(_singleGlossary(lookup, base));
      }
      return _singleGlossary(lookup, dictionary);
    }

    switch (handlebar) {
      case '{expression}':
        return lookup.expression;
      case '{reading}':
        return lookup.reading;
      case '{furigana-plain}':
        return lookup.readingPlain;
      case '{glossary}':
        return lookup.glossary;
      case '{glossary-brief}':
        return _stripGlossaryHeaders(lookup.glossary);
      case '{glossary-no-dictionary}':
        return _stripDictionaryName(lookup.glossary);
      case '{glossary-first}':
        return _firstGlossary(lookup, termGlossaries);
      case '{glossary-first-brief}':
        return _stripGlossaryHeaders(_firstGlossary(lookup, termGlossaries));
      case '{glossary-first-no-dictionary}':
        return _stripDictionaryName(_firstGlossary(lookup, termGlossaries));
      case '{monolingual-definition}':
        return _firstGlossary(lookup, termGlossaries, category: DictionaryCategory.monolingual);
      case '{monolingual-definition-brief}':
        return _stripGlossaryHeaders(_firstGlossary(lookup, termGlossaries, category: DictionaryCategory.monolingual));
      case '{bilingual-definition}':
        return _firstGlossary(lookup, termGlossaries, category: DictionaryCategory.bilingual);
      case '{bilingual-definition-brief}':
        return _stripGlossaryHeaders(_firstGlossary(lookup, termGlossaries, category: DictionaryCategory.bilingual));
      case '{monolingual-definition-fallback}':
        return _firstGlossaryWithFallback(
          lookup,
          termGlossaries,
          preferred: DictionaryCategory.monolingual,
          fallback: DictionaryCategory.bilingual,
        );
      case '{bilingual-definition-fallback}':
        return _firstGlossaryWithFallback(
          lookup,
          termGlossaries,
          preferred: DictionaryCategory.bilingual,
          fallback: DictionaryCategory.monolingual,
        );
      case '{selected-glossary}':
        return _selectedGlossaryOrConfiguredFallback(
          lookup,
          context,
          selectedGlossaryFallback,
          termGlossaries,
        );
      case '{selected-glossary-fallback}':
        return _singleGlossary(lookup, lookup.selectedDictionary).isNotEmpty ? _singleGlossary(lookup, lookup.selectedDictionary) : lookup.glossaryFirst;
      case '{selected-glossary-brief}':
        return _stripGlossaryHeaders(
          _selectedGlossaryOrConfiguredFallback(lookup, context, selectedGlossaryFallback, termGlossaries),
        );
      case '{popup-selection-text}':
        return lookup.popupSelectionText;
      case '{sentence}':
        return _sentenceValue(lookup, context);
      case '{sentence-translation}':
        return lookup.sentenceTranslation;
      case '{cloze-prefix}':
        return _clozeParts(lookup, context).prefix;
      case '{cloze-body}':
        return _clozeParts(lookup, context).body;
      case '{cloze-suffix}':
        return _clozeParts(lookup, context).suffix;
      case '{frequencies}':
        return lookup.frequenciesHtml;
      case '{frequency-harmonic-rank}':
        return lookup.frequencyHarmonicRank;
      case '{document-title}':
        return context.documentTitle;
      case '{book-cover}':
        return context.coverPath ?? '';
      case '{sentence-image}':
        return context.sentenceImagePath ?? lookup.sentenceImagePath ?? '';
      case '{audio}':
        return lookup.wordAudioPath ?? '';
      case '{audio-clip}':
        return context.audioClipPath ?? lookup.audioClipPath ?? '';
      default:
        return '';
    }
  }

  static String _singleGlossary(WordLookupResult lookup, String dictionary) {
    if (dictionary.trim().isEmpty) return '';
    final direct = lookup.singleGlossaries[dictionary];
    if (direct != null && direct.isNotEmpty) return direct;
    final normalized = _normalizeDictionaryName(dictionary);
    for (final entry in lookup.singleGlossaries.entries) {
      if (_normalizeDictionaryName(entry.key) == normalized) return entry.value;
    }
    return '';
  }

  /// 第一条符合 [category] 条件的释义。[category] 为 null 时取任意非排除词典的第一条。
  static String _firstGlossary(
    WordLookupResult lookup,
    List<WordLookupGlossary> termGlossaries, {
    DictionaryCategory? category,
  }) {
    if (termGlossaries.isEmpty) {
      if (category == null) return lookup.glossaryFirst;
      return '';
    }
    for (final glossary in termGlossaries) {
      if (glossary.category == DictionaryCategory.exclude) continue;
      if (category != null && glossary.category != category) continue;
      final value = glossary.html.isNotEmpty ? glossary.html : _singleGlossary(lookup, glossary.dictionary);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _firstGlossaryWithFallback(
    WordLookupResult lookup,
    List<WordLookupGlossary> termGlossaries, {
    required DictionaryCategory preferred,
    required DictionaryCategory fallback,
  }) {
    final first = _firstGlossary(lookup, termGlossaries, category: preferred);
    if (first.isNotEmpty) return first;
    return _firstGlossary(lookup, termGlossaries, category: fallback);
  }

  static String _selectedGlossaryOrConfiguredFallback(
    WordLookupResult lookup,
    AnkiMiningContext context,
    String selectedGlossaryFallback,
    List<WordLookupGlossary> termGlossaries,
  ) {
    final selected = _singleGlossary(lookup, lookup.selectedDictionary);
    if (selected.isNotEmpty) return selected;
    // -- 回退配置本身就是 selected-glossary 系列，再解析一次只会绕回这里。
    if (selectedGlossaryFallback.isEmpty || _selectedGlossaryHandlebars.contains(selectedGlossaryFallback)) {
      return '';
    }
    return _resolve(
      selectedGlossaryFallback,
      lookup: lookup,
      context: context,
      selectedGlossaryFallback: '',
      termGlossaries: termGlossaries,
    );
  }

  /// 例句，命中词用 `<b>` 包起来。
  static String _sentenceValue(WordLookupResult lookup, AnkiMiningContext context) {
    final parts = _clozeParts(lookup, context);
    if (parts.body.isEmpty) return parts.sentence;
    return '${parts.prefix}<b>${parts.body}</b>${parts.suffix}';
  }

  static _AnkiClozeParts _clozeParts(WordLookupResult lookup, AnkiMiningContext context) {
    final sentence = context.sentence.isNotEmpty ? context.sentence : lookup.sentence;
    final matched = lookup.matched.isNotEmpty ? lookup.matched : lookup.expression;
    if (matched.isEmpty) return _AnkiClozeParts(sentence: sentence, prefix: sentence, body: '', suffix: '');
    if (sentence.isEmpty) return _AnkiClozeParts(sentence: '', prefix: '', body: '', suffix: '');

    var start = -1;
    final offset = context.sentenceOffset ?? lookup.sentenceOffset;
    if (offset != null && offset >= 0 && offset + matched.length <= sentence.length) {
      if (sentence.startsWith(matched, offset)) start = offset;
    }
    if (start == -1) start = sentence.indexOf(matched);
    if (start == -1) return _AnkiClozeParts(sentence: sentence, prefix: sentence, body: '', suffix: '');

    return _AnkiClozeParts(
      sentence: sentence,
      prefix: sentence.substring(0, start),
      body: sentence.substring(start, start + matched.length),
      suffix: sentence.substring(start + matched.length),
    );
  }

  /// 去掉释义条目前面的词典名标签，保留条目本身。
  static String _stripGlossaryHeaders(String html) => html.replaceAll(_glossaryHeaderRegex, r'$1');

  /// 把 `<i>JMdict, XYZ)</i>` 里的 `, XYZ)` 摘掉。
  static String _stripDictionaryName(String html) {
    return html.replaceAllMapped(_dictionaryLabelRegex, (match) {
      final dict = match.group(1)!;
      final label = match.group(2)!;
      final stripped = label.replaceFirst(', $dict)', ')');
      if (stripped == '($dict)') return '<li data-dictionary="$dict">';
      return '<li data-dictionary="$dict"><i>$stripped</i> ';
    });
  }

  /// 词典名后面可能带 ` [tag]`，比较时忽略。
  static String _normalizeDictionaryName(String name) => name.trim().replaceAll(_dictionaryNameSuffixRegex, '');

  static final RegExp _dictionaryNameSuffixRegex = RegExp(r'\s*\[[^]]+]\s*$');
}

class _AnkiClozeParts {
  final String sentence;
  final String prefix;
  final String body;
  final String suffix;

  const _AnkiClozeParts({required this.sentence, required this.prefix, required this.body, required this.suffix});
}

/// 字段模板 -> 已渲染字段。只输出卡片类型真正拥有的字段，模板里多写的会被忽略。
class AnkiFieldRenderer {
  const AnkiFieldRenderer._();

  static AnkiRenderedFields renderFields({
    required AnkiNoteType noteType,
    required Map<String, String> fieldMappings,
    required WordLookupResult lookup,
    required AnkiMiningContext context,
    String selectedGlossaryFallback = '',
    List<WordLookupGlossary> termGlossaries = const [],
  }) {
    final fields = <String, String>{};
    for (final field in noteType.fields) {
      final template = fieldMappings[field];
      fields[field] = template == null
          ? ''
          : AnkiHandlebarRenderer.render(
              template,
              lookup: lookup,
              context: context,
              selectedGlossaryFallback: selectedGlossaryFallback,
              termGlossaries: termGlossaries,
            );
    }
    return AnkiRenderedFields(fields: fields);
  }
}
