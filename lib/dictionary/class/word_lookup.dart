/// 查词（word lookup）领域模型与接口。
///
/// 这层刻意只定义**契约**，不绑定任何具体词典实现：
/// 上层（点词弹窗、转录句子、制卡按钮）只依赖 [WordLookupProvider]，
/// 具体词典（本地 Yomitan 词典库、在线 API、后续接上的转录文本）作为实现注册进 [WordLookupRegistry]。
library;

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';

/// 一次查词请求。
class WordLookupRequest {
  /// 被点中的词语本身（例句里的原样形态，可能带浊音/长音符）。
  final String expression;

  /// 完整例句。没有时为空串（很多场景没有上下文，例如用户在搜索框输入）。
  final String sentence;

  /// [expression] 在 [sentence] 中的偏移。未知时传 null。
  final int? sentenceOffset;

  /// 语言提示，影响选词典。空串表示不限定。
  final String language;

  /// 来源标识，用于词典打分（例如 `audiobook`、`lyrics`、`video`）。
  final String source;

  const WordLookupRequest({
    required this.expression,
    this.sentence = '',
    this.sentenceOffset,
    this.language = '',
    this.source = '',
  });
}

/// 单个词典给出的释义条目。
class WordLookupGlossary {
  /// 词典名，显示在释义前面，也会用于 `{single-glossary-XXX}`。
  final String dictionary;

  /// 该词典归类，决定 `{monolingual-definition}` / `{bilingual-definition}` 选谁。
  final DictionaryCategory category;

  /// HTML 片段。
  final String html;

  const WordLookupGlossary({
    required this.dictionary,
    required this.html,
    this.category = DictionaryCategory.unspecified,
  });

  factory WordLookupGlossary.fromJson(Map<String, dynamic> json) => WordLookupGlossary(
    dictionary: json['dictionary'] as String? ?? '',
    category: DictionaryCategory.fromName(json['category'] as String?),
    html: json['html'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'dictionary': dictionary, 'category': category.name, 'html': html};
}

/// 词典归类。
enum DictionaryCategory {
  unspecified,
  monolingual,
  bilingual,
  /// 明确排除，不参与 `{glossary-first}` 之类的选择。
  exclude;

  static DictionaryCategory fromName(String? name) {
    if (name == null) return unspecified;
    for (final value in DictionaryCategory.values) {
      if (value.name == name) return value;
    }
    return unspecified;
  }
}

/// 一次查词的完整结果，也就是喂给字段模板的载荷。
class WordLookupResult {
  /// 归一化后的词条（日语取汉字/假名本体的读音体，英语取原词）。
  final String expression;

  /// 读音。日语假名、汉字的拼音注音等。
  final String reading;

  /// 去掉注音后的纯文本，例如 `日本語` 而不是 `にほんご`。
  final String readingPlain;

  /// 在原句里实际命中的子串，可能比 [expression] 短（点到了词的一部分）。
  final String matched;

  /// 例句，没有时回落到 [WordLookupRequest.sentence]。
  final String sentence;

  /// [matched] 在 [sentence] 中的偏移。
  final int? sentenceOffset;

  /// 例句翻译。
  final String sentenceTranslation;

  /// 例句截图的本地绝对路径（有听书/视频画面时可填）。
  final String? sentenceImagePath;

  /// 单词发音音频的本地绝对路径。
  final String? wordAudioPath;

  /// 例句音频片段的本地绝对路径（听书按时间轴截的片段）。
  final String? audioClipPath;

  /// 词频 HTML / 排名文本。
  final String frequenciesHtml;
  final String frequencyHarmonicRank;

  /// 全部词典释义拼起来的 HTML。
  final String glossary;

  /// 第一条释义（不含词典名标签）的 HTML。
  final String glossaryFirst;

  /// 按词典名分开的释义，供 `{single-glossary-XXX}` 使用。
  final Map<String, String> singleGlossaries;

  /// 查词弹窗里用户当时实际选中的文本（点词可能是选中文本）。
  final String popupSelectionText;

  /// 结果来自哪个词典，用于 `{selected-glossary}`。
  final String selectedDictionary;

  const WordLookupResult({
    required this.expression,
    this.reading = '',
    this.readingPlain = '',
    this.matched = '',
    this.sentence = '',
    this.sentenceOffset,
    this.sentenceTranslation = '',
    this.sentenceImagePath,
    this.wordAudioPath,
    this.audioClipPath,
    this.frequenciesHtml = '',
    this.frequencyHarmonicRank = '',
    this.glossary = '',
    this.glossaryFirst = '',
    this.singleGlossaries = const {},
    this.popupSelectionText = '',
    this.selectedDictionary = '',
  });

  factory WordLookupResult.fromJson(Map<String, dynamic> json) => WordLookupResult(
    expression: json['expression'] as String? ?? '',
    reading: json['reading'] as String? ?? '',
    readingPlain: json['readingPlain'] as String? ?? '',
    matched: json['matched'] as String? ?? '',
    sentence: json['sentence'] as String? ?? '',
    sentenceOffset: (json['sentenceOffset'] as num?)?.toInt(),
    sentenceTranslation: json['sentenceTranslation'] as String? ?? '',
    sentenceImagePath: json['sentenceImagePath'] as String?,
    wordAudioPath: json['wordAudioPath'] as String?,
    audioClipPath: json['audioClipPath'] as String?,
    frequenciesHtml: json['frequenciesHtml'] as String? ?? '',
    frequencyHarmonicRank: json['frequencyHarmonicRank'] as String? ?? '',
    glossary: json['glossary'] as String? ?? '',
    glossaryFirst: json['glossaryFirst'] as String? ?? '',
    singleGlossaries: switch (json['singleGlossaries']) {
      final Map m => {for (final e in m.entries) '${e.key}': '${e.value}'},
      _ => const {},
    },
    popupSelectionText: json['popupSelectionText'] as String? ?? '',
    selectedDictionary: json['selectedDictionary'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'expression': expression,
    'reading': reading,
    'readingPlain': readingPlain,
    'matched': matched,
    'sentence': sentence,
    'sentenceOffset': sentenceOffset,
    'sentenceTranslation': sentenceTranslation,
    'sentenceImagePath': sentenceImagePath,
    'wordAudioPath': wordAudioPath,
    'audioClipPath': audioClipPath,
    'frequenciesHtml': frequenciesHtml,
    'frequencyHarmonicRank': frequencyHarmonicRank,
    'glossary': glossary,
    'glossaryFirst': glossaryFirst,
    'singleGlossaries': singleGlossaries,
    'popupSelectionText': popupSelectionText,
    'selectedDictionary': selectedDictionary,
  };

  /// 从查词结果 + 请求上下文组装出制卡载荷。
  ///
  /// 词典实现只管查词，例句/截图/音频这些"来源侧"的媒体由 [WordLookupRequest] 之外的
  /// [AnkiMiningContext] 提供，这里做兜底合并。
  WordLookupResult mergedWith({String? sentence, int? sentenceOffset, String? sentenceImagePath, String? audioClipPath}) {
    return WordLookupResult(
      expression: expression,
      reading: reading,
      readingPlain: readingPlain,
      matched: matched,
      sentence: this.sentence.isNotEmpty ? this.sentence : (sentence ?? ''),
      sentenceOffset: this.sentenceOffset ?? sentenceOffset,
      sentenceTranslation: sentenceTranslation,
      sentenceImagePath: this.sentenceImagePath ?? sentenceImagePath,
      wordAudioPath: wordAudioPath,
      audioClipPath: this.audioClipPath ?? audioClipPath,
      frequenciesHtml: frequenciesHtml,
      frequencyHarmonicRank: frequencyHarmonicRank,
      glossary: glossary,
      glossaryFirst: glossaryFirst,
      singleGlossaries: singleGlossaries,
      popupSelectionText: popupSelectionText,
      selectedDictionary: selectedDictionary,
    );
  }

  /// 媒体入库后用 Anki 的真实引用覆盖本地路径。
  WordLookupResult copyWith({
    String? sentence,
    int? sentenceOffset,
    String? sentenceImagePath,
    String? wordAudioPath,
    String? audioClipPath,
  }) =>
      WordLookupResult(
        expression: expression,
        reading: reading,
        readingPlain: readingPlain,
        matched: matched,
        sentence: sentence ?? this.sentence,
        sentenceOffset: sentenceOffset ?? this.sentenceOffset,
        sentenceTranslation: sentenceTranslation,
        sentenceImagePath: sentenceImagePath ?? this.sentenceImagePath,
        wordAudioPath: wordAudioPath ?? this.wordAudioPath,
        audioClipPath: audioClipPath ?? this.audioClipPath,
        frequenciesHtml: frequenciesHtml,
        frequencyHarmonicRank: frequencyHarmonicRank,
        glossary: glossary,
        glossaryFirst: glossaryFirst,
        singleGlossaries: singleGlossaries,
        popupSelectionText: popupSelectionText,
        selectedDictionary: selectedDictionary,
      );
}


/// 词典提供方契约。
///
/// 实现方负责「给一个词，返回释义」。媒体（音频/截图）由调用方准备好后塞进请求之外，
/// 所以词典实现不需要碰文件系统。
abstract class WordLookupProvider {
  /// 稳定 id，用于设置界面选择来源。
  String get id;

  /// 展示名。
  String get displayName;

  /// 是否可用（例如本地词典文件是否已安装）。
  bool get isAvailable;

  /// 这个词典是否声明支持某种语言，空串表示不限。
  String get language;

  /// 查词。[request] 里的例句与偏移应当被透传给词典，用于取上下文体例。
  Future<WordLookupResult?> lookup(WordLookupRequest request);
}

/// 词典注册表。
///
/// 优先使用第一个 `isAvailable` 的实现；也可以按语言精确挑选。
class WordLookupRegistry {
  WordLookupRegistry._internal();

  static final WordLookupRegistry inst = WordLookupRegistry._internal();

  final _providers = <WordLookupProvider>[];

  List<WordLookupProvider> get providers => List.unmodifiable(_providers);

  void register(WordLookupProvider provider) {
    _providers.removeWhere((e) => e.id == provider.id);
    _providers.add(provider);
  }

  void unregister(String id) => _providers.removeWhere((e) => e.id == id);

  /// 挑一个能处理 [request] 的词典：语言匹配优先，否则取第一个可用的。
  WordLookupProvider? resolveFor(WordLookupRequest request) {
    if (_providers.isEmpty) return null;
    final lang = request.language.trim();
    if (lang.isNotEmpty) {
      final matched = _providers.where((e) => e.language == lang && e.isAvailable);
      if (matched.isNotEmpty) return matched.first;
    }
    return _providers.firstWhereOrNull((e) => e.isAvailable);
  }

  /// 依次询问可用词典，返回第一个非空结果。
  Future<WordLookupResult?> lookup(WordLookupRequest request) async {
    final primary = resolveFor(request);
    if (primary == null) return null;
    final result = await primary.lookup(request);
    if (result != null) return result;

    // -- 主词典没查到，退回其余可用词典，不至于直接空手。
    for (final provider in _providers) {
      if (identical(provider, primary) || !provider.isAvailable) continue;
      final fallback = await provider.lookup(request);
      if (fallback != null) return fallback;
    }
    return null;
  }
}
