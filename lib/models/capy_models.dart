/// CapyPlayer / Forward Widget 数据模型。
///
/// 字段别名按官方规范做兜底（posterUrl -> posterPath -> poster_url -> poster），
/// 这样第三方组件无论按哪一套字段返回都能吃下。
library;

dynamic _first(Map map, List<String> keys) {
  for (final k in keys) {
    final v = map[k];
    if (v != null && v != '') return v;
  }
  return null;
}

String _str(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return fallback;
}

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

double? _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

List<dynamic> _list(dynamic v) => v is List ? v : const [];

/// 一条媒体条目。
class MediaItem {
  MediaItem({
    required this.id,
    required this.title,
    this.type = 'url',
    this.mediaType = 'movie',
    this.posterUrl = '',
    this.backdropUrl = '',
    this.description = '',
    this.remark = '',
    this.rating,
    this.releaseDate = '',
    this.genreTitle = '',
    this.link = '',
    this.videoUrl = '',
    this.customHeaders = const {},
    this.playerType = 'system',
    this.episode,
    this.duration,
  });

  final String id;
  final String title;

  /// url / link / tmdb / douban / imdb
  final String type;

  /// movie / tv
  final String mediaType;
  final String posterUrl;
  final String backdropUrl;
  final String description;
  final String remark;
  final double? rating;
  final String releaseDate;
  final String genreTitle;

  /// 详情链接（需要再走 loadDetail）
  final String link;

  /// 直链可播
  final String videoUrl;
  final Map<String, String> customHeaders;
  final String playerType;
  final int? episode;
  final int? duration;

  bool get isPlayable => videoUrl.isNotEmpty;
  bool get needsDetail => videoUrl.isEmpty && link.isNotEmpty;

  factory MediaItem.fromJson(Map json) {
    final headers = <String, String>{};
    final h = _first(json, const ['customHeaders', 'headers', 'custom_headers']);
    if (h is Map) {
      h.forEach((k, v) => headers[_str(k)] = _str(v));
    }
    return MediaItem(
      id: _str(_first(json, const ['id', 'mediaId', 'media_id'])),
      title: _str(_first(json, const ['title', 'name'])),
      type: _str(_first(json, const ['type']), 'url'),
      mediaType: _str(_first(json, const ['mediaType', 'media_type']), 'movie'),
      posterUrl: _str(_first(json, const ['posterUrl', 'poster_url', 'poster', 'posterPath'])),
      backdropUrl: _str(_first(json, const ['backdropUrl', 'backdrop_url', 'backdrop', 'coverUrl', 'backdropPath'])),
      description: _str(_first(json, const ['description', 'overview', 'summary'])),
      remark: _str(_first(json, const ['remark', 'note', 'subtitle'])),
      rating: _double(_first(json, const ['rating', 'score'])),
      releaseDate: _str(_first(json, const ['releaseDate', 'release_date', 'date'])),
      genreTitle: _str(_first(json, const ['genreTitle', 'genre', 'category'])),
      link: _str(_first(json, const ['link', 'url', 'detailUrl'])),
      videoUrl: _str(_first(json, const ['videoUrl', 'video_url'])),
      customHeaders: headers,
      playerType: _str(_first(json, const ['playerType']), 'system'),
      episode: _int(_first(json, const ['episode']), 0) == 0 ? null : _int(_first(json, const ['episode'])),
      duration: _int(_first(json, const ['duration']), 0) == 0 ? null : _int(_first(json, const ['duration'])),
    );
  }

  static MediaItem? tryParse(dynamic raw) {
    if (raw is Map) {
      final item = MediaItem.fromJson(raw.cast<String, dynamic>());
      if (item.title.isEmpty && item.id.isEmpty) return null;
      return item;
    }
    return null;
  }

  static List<MediaItem> listFrom(dynamic raw) {
    return _list(raw).map(tryParse).whereType<MediaItem>().toList();
  }
}

/// 一条播放线路。
class PlaySource {
  PlaySource({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.isDefault = false,
    this.customHeaders = const {},
    this.playerType = 'system',
    this.description = '',
  });

  final String id;
  final String title;
  final String videoUrl;
  final bool isDefault;
  final Map<String, String> customHeaders;
  final String playerType;
  final String description;

  factory PlaySource.fromJson(Map json, int index) {
    final headers = <String, String>{};
    final h = _first(json, const ['customHeaders', 'headers']);
    if (h is Map) h.forEach((k, v) => headers[_str(k)] = _str(v));
    return PlaySource(
      id: _str(_first(json, const ['id', 'sourceId', 'source_id']), 'src-$index'),
      title: _str(_first(json, const ['title', 'name', 'label']), '线路 ${index + 1}'),
      videoUrl: _str(_first(json, const ['videoUrl', 'video_url', 'url', 'path', 'link'])),
      isDefault: _first(json, const ['isDefault', 'is_default']) == true,
      customHeaders: headers,
      playerType: _str(_first(json, const ['playerType']), 'system'),
      description: _str(_first(json, const ['description'])),
    );
  }
}

/// 一集。
class Episode {
  Episode({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.episodeNumber,
    required this.seasonNumber,
    this.customHeaders = const {},
    this.posterUrl = '',
  });

  final String id;
  final String title;
  final String videoUrl;
  final int episodeNumber;
  final int seasonNumber;
  final Map<String, String> customHeaders;
  final String posterUrl;

  factory Episode.fromJson(Map json, {int defaultSeason = 1}) {
    final url = _str(_first(json, const ['videoUrl', 'video_url', 'mediaUrl', 'streamUrl', 'url', 'link']));
    final headers = <String, String>{};
    final h = _first(json, const ['customHeaders', 'headers']);
    if (h is Map) h.forEach((k, v) => headers[_str(k)] = _str(v));
    final num = _int(_first(json, const ['episodeNumber', 'episode', 'index', 'episode_number']), 1);
    return Episode(
      id: _str(_first(json, const ['id']), url.isNotEmpty ? url : 'ep-$num'),
      title: _str(_first(json, const ['title', 'name']), '第 $num 集'),
      videoUrl: url,
      episodeNumber: num,
      seasonNumber: _int(_first(json, const ['seasonNumber', 'season', 'season_number']), defaultSeason),
      customHeaders: headers,
      posterUrl: _str(_first(json, const ['posterUrl', 'poster_url', 'poster', 'posterPath'])),
    );
  }

  static List<Episode> listFrom(dynamic raw, {int defaultSeason = 1}) {
    final out = <Episode>[];
    for (final e in _list(raw)) {
      if (e is Map) {
        final ep = Episode.fromJson(e.cast<String, dynamic>(), defaultSeason: defaultSeason);
        if (ep.videoUrl.isNotEmpty) out.add(ep);
      }
    }
    return out;
  }
}

class Season {
  Season({required this.seasonNumber, required this.title, required this.episodes});

  final int seasonNumber;
  final String title;
  final List<Episode> episodes;

  factory Season.fromJson(Map json, int index) {
    final number = _int(_first(json, const ['seasonNumber', 'season', 'season_number']), index + 1);
    return Season(
      seasonNumber: number,
      title: _str(_first(json, const ['title', 'name']), '第 $number 季'),
      episodes: Episode.listFrom(json['episodes'], defaultSeason: number),
    );
  }
}

/// loadDetail 的返回。
class CapyDetail {
  CapyDetail({
    required this.title,
    this.mediaType = 'tv',
    this.posterUrl = '',
    this.backdropUrl = '',
    this.description = '',
    this.videoUrl = '',
    this.playSources = const [],
    this.seasons = const [],
    this.episodes = const [],
    this.tags = const [],
    this.customHeaders = const {},
    this.playerType = '',
  });

  final String title;
  final String mediaType;
  final String posterUrl;
  final String backdropUrl;
  final String description;
  final String videoUrl;
  final List<PlaySource> playSources;
  final List<Season> seasons;

  /// 单季聚合结构（episodeItems）
  final List<Episode> episodes;
  final List<String> tags;
  final Map<String, String> customHeaders;

  /// 组件对「这条详情该怎么播」的声明（system / mpv / none）。
  /// MissAV 会在这里给 `system`，而列表项给的是 `none` —— 播放时应以详情为准。
  final String playerType;

  bool get hasVideo => videoUrl.isNotEmpty;
  bool get hasSeasons => seasons.isNotEmpty;
  bool get hasEpisodes => episodes.isNotEmpty;
  bool get hasSources => playSources.isNotEmpty;

  factory CapyDetail.fromJson(Map json) {
    final headers = <String, String>{};
    final h = _first(json, const ['customHeaders', 'headers']);
    if (h is Map) h.forEach((k, v) => headers[_str(k)] = _str(v));

    final sources = <PlaySource>[];
    final rawSources = _list(_first(json, const ['playSources', 'play_sources']));
    if (rawSources.isNotEmpty) {
      for (var i = 0; i < rawSources.length; i++) {
        final s = rawSources[i];
        if (s is Map) {
          final ps = PlaySource.fromJson(s.cast<String, dynamic>(), i);
          if (ps.videoUrl.isNotEmpty) sources.add(ps);
        }
      }
    }

    final seasons = <Season>[];
    final rawSeasons = _list(json['seasons']);
    for (var i = 0; i < rawSeasons.length; i++) {
      final s = rawSeasons[i];
      if (s is Map) seasons.add(Season.fromJson(s.cast<String, dynamic>(), i));
    }

    var episodes = Episode.listFrom(_first(json, const ['episodeItems', 'episodes']));
    // 没有 seasons 时，若顶层是“多线路数组”，由调用方处理；这里做单季兜底
    if (seasons.isEmpty && episodes.isEmpty) {
      episodes = Episode.listFrom(json['episodes']);
    }

    final tags = <String>[];
    final rawTags = _first(json, const ['tags']);
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String && t.isNotEmpty) tags.add(t);
      }
    } else if (rawTags is String && rawTags.isNotEmpty) {
      tags.add(rawTags);
    }

    return CapyDetail(
      title: _str(_first(json, const ['title', 'name'])),
      mediaType: _str(_first(json, const ['mediaType', 'media_type']), 'tv'),
      posterUrl: _str(_first(json, const ['posterUrl', 'poster_url', 'poster', 'posterPath'])),
      backdropUrl: _str(_first(json, const ['backdropUrl', 'backdrop_url', 'backdrop', 'backdropPath'])),
      description: _str(_first(json, const ['description', 'overview'])),
      videoUrl: _str(_first(json, const ['videoUrl', 'video_url'])),
      playSources: sources,
      seasons: seasons,
      episodes: episodes,
      tags: tags,
      customHeaders: headers,
      playerType: _str(_first(json, const ['playerType', 'player_type'])),
    );
  }

  List<Episode> get allEpisodes {
    if (seasons.isNotEmpty) {
      return seasons.expand((s) => s.episodes).toList();
    }
    return episodes;
  }
}

/// 组件参数声明。
class CapyParam {
  CapyParam({
    required this.name,
    required this.type,
    required this.title,
    this.defaultValue = '',
    this.required = false,
    this.value = '',
    this.enumOptions = const [],
  });

  final String name;
  final String type; // input / constant / enumeration / count / page / offset
  final String title;
  final String defaultValue;
  final bool required;
  final String value;
  final List<CapyEnumOption> enumOptions;

  factory CapyParam.fromJson(Map json) {
    final options = <CapyEnumOption>[];
    final raw = _first(json, const ['enumOptions', 'enumValues', 'placeholders']);
    for (final o in _list(raw)) {
      if (o is Map) {
        options.add(CapyEnumOption(title: _str(_first(o, const ['title', 'name'])), value: _str(_first(o, const ['value']))));
      } else if (o is String) {
        options.add(CapyEnumOption(title: o, value: o));
      }
    }
    return CapyParam(
      name: _str(json['name']),
      type: _str(json['type'], 'input'),
      title: _str(_first(json, const ['title', 'label', 'name'])),
      defaultValue: _str(_first(json, const ['defaultValue', 'value', 'default'])),
      required: json['required'] == true,
      value: _str(_first(json, const ['value', 'defaultValue'])),
      enumOptions: options,
    );
  }
}

class CapyEnumOption {
  CapyEnumOption({required this.title, required this.value});
  final String title;
  final String value;
}

/// 一个模块（= UI 上的一个"分类/入口"）。
class CapyModule {
  CapyModule({
    required this.id,
    required this.title,
    required this.functionName,
    this.type = 'media_list',
    this.description = '',
    this.params = const [],
    this.cacheDuration = 3600,
  });

  final String id;
  final String title;
  final String functionName;
  final String type;
  final String description;
  final List<CapyParam> params;
  final int cacheDuration;

  static final RegExp _searchWord = RegExp(r'search|搜索|查找|搜片|检索', caseSensitive: false);
  static final RegExp _historyWord = RegExp(r'history|继续观看|观看记录|播放记录|历史|收藏|favorite|bookmark', caseSensitive: false);
  static const Set<String> _searchParamNames = <String>{
    'keyword', 'query', 'q', 'wd', 'kw', 'key', 'searchkey', 'search_key',
  };

  /// 搜索型模块：标题/函数名带 search 字样，或声明了关键词类参数。
  bool get looksLikeSearch =>
      _searchWord.hasMatch('$id $title $functionName') ||
      params.any((p) => _searchParamNames.contains(p.name.toLowerCase()));

  /// 「我的/历史」型模块：第一屏放它通常是空的，不适合当首页。
  bool get looksLikeHistory => _historyWord.hasMatch('$id $title $functionName');

  factory CapyModule.fromJson(Map json) {
    final params = <CapyParam>[];
    for (final p in _list(json['params'])) {
      if (p is Map) params.add(CapyParam.fromJson(p.cast<String, dynamic>()));
    }
    return CapyModule(
      id: _str(_first(json, const ['id', 'functionName'])),
      title: _str(_first(json, const ['title', 'name']), _str(json['functionName'])),
      functionName: _str(json['functionName']),
      type: _str(json['type'], 'media_list'),
      description: _str(json['description']),
      params: params,
      cacheDuration: _int(json['cacheDuration'], 3600),
    );
  }
}

/// WidgetMetadata。
class WidgetMeta {
  WidgetMeta({
    required this.id,
    required this.title,
    required this.version,
    required this.modules,
    this.description = '',
    this.icon = '',
    this.site = '',
    this.author = '',
    this.globalParams = const [],
    this.searchFunctionName = '',
  });

  final String id;
  final String title;
  final String version;
  final String description;
  final String icon;
  final String site;
  final String author;
  final List<CapyModule> modules;
  final List<CapyParam> globalParams;
  final String searchFunctionName;

  factory WidgetMeta.fromJson(Map json) {
    final modules = <CapyModule>[];
    for (final m in _list(json['modules'])) {
      if (m is Map) {
        final mod = CapyModule.fromJson(m.cast<String, dynamic>());
        if (mod.functionName.isNotEmpty) modules.add(mod);
      }
    }
    final globals = <CapyParam>[];
    for (final p in _list(json['globalParams'])) {
      if (p is Map) globals.add(CapyParam.fromJson(p.cast<String, dynamic>()));
    }
    var searchFn = '';
    final search = json['search'];
    if (search is Map) {
      searchFn = _str(search['functionName']);
    }
    return WidgetMeta(
      id: _str(json['id'], _str(json['title'])),
      title: _str(_first(json, const ['title', 'name']), '未命名组件'),
      version: _str(json['version'], '1.0.0'),
      description: _str(json['description']),
      icon: _str(_first(json, const ['icon', 'iconUrl'])),
      site: _str(json['site']),
      author: _str(json['author']),
      modules: modules,
      globalParams: globals,
      searchFunctionName: searchFn,
    );
  }
}

/// 首页该用哪个模块。
///
/// 组件作者常把「搜索」放在 modules[0]（红果短剧、MissAV 都是这样），宿主若直接
/// 拿第一个模块当首页，空关键词下必然得到空列表 —— 表现为首页一片空白。
/// 这里按「非搜索非历史 → 非搜索 → 第一个」三级回退挑一个真正的列表模块。
CapyModule? pickHomeModule(List<CapyModule> modules) {
  if (modules.isEmpty) return null;
  for (final module in modules) {
    if (!module.looksLikeSearch && !module.looksLikeHistory) return module;
  }
  for (final module in modules) {
    if (!module.looksLikeSearch) return module;
  }
  return modules.first;
}
