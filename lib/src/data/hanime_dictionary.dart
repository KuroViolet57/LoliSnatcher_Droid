import 'package:lolisnatcher/src/data/tag_type.dart';

/// The complete hanime1.me tag vocabulary, translated.
///
/// This is what makes English-first use of a Chinese-only site possible
/// WITHOUT a translation service: the site's search form enumerates its
/// entire tag vocabulary — 240 tags in seven fixed groups, plus genres and
/// sort orders — so the whole thing fits in one hand-checked dictionary.
/// Tags are displayed in English, searched in English, and mapped back to
/// the exact Chinese strings the site expects at request time.
///
/// Every entry was extracted from the live `/search` form. Free text
/// (titles, artist names) is NOT dictionary work and is handled separately.
class HanimeTag {
  const HanimeTag(this.zh, this.en, this.type);

  /// The exact string the site uses in `tags[]`.
  final String zh;

  /// Booru-style English token (underscored, lowercase).
  final String en;

  final TagType type;
}

class HanimeDictionary {
  HanimeDictionary._();

  /// group 影片屬性 (video attributes) -> meta; everything else is a normal
  /// descriptive tag. The "character" entries are archetypes (maid, nurse),
  /// not named characters, so they stay general like on any booru.
  static const List<HanimeTag> tags = [
    // ── 影片屬性 · video attributes ──
    HanimeTag('無碼', 'uncensored', TagType.meta),
    HanimeTag('AI解碼', 'ai_decensored', TagType.meta),
    HanimeTag('中文字幕', 'chinese_subtitles', TagType.meta),
    HanimeTag('中文配音', 'chinese_dub', TagType.meta),
    HanimeTag('同人作品', 'doujin', TagType.meta),
    HanimeTag('斷面圖', 'cross_section', TagType.meta),
    HanimeTag('ASMR', 'asmr', TagType.meta),
    HanimeTag('1080p', '1080p', TagType.meta),
    HanimeTag('60FPS', '60fps', TagType.meta),
    // ── 人物關係 · relationships ──
    HanimeTag('近親', 'incest', TagType.none),
    HanimeTag('姐', 'older_sister', TagType.none),
    HanimeTag('妹', 'younger_sister', TagType.none),
    HanimeTag('母', 'mother', TagType.none),
    HanimeTag('女兒', 'daughter', TagType.none),
    HanimeTag('師生', 'teacher_and_student', TagType.none),
    HanimeTag('情侶', 'couple', TagType.none),
    HanimeTag('青梅竹馬', 'childhood_friend', TagType.none),
    HanimeTag('同事', 'coworker', TagType.none),
    // ── 角色設定 · character archetypes ──
    HanimeTag('JK', 'schoolgirl', TagType.none),
    HanimeTag('處女', 'virgin', TagType.none),
    HanimeTag('御姐', 'onee-san', TagType.none),
    HanimeTag('熟女', 'milf', TagType.none),
    HanimeTag('人妻', 'married_woman', TagType.none),
    HanimeTag('女教師', 'female_teacher', TagType.none),
    HanimeTag('男教師', 'male_teacher', TagType.none),
    HanimeTag('女醫生', 'female_doctor', TagType.none),
    HanimeTag('女病人', 'female_patient', TagType.none),
    HanimeTag('護士', 'nurse', TagType.none),
    HanimeTag('OL', 'office_lady', TagType.none),
    HanimeTag('女警', 'policewoman', TagType.none),
    HanimeTag('大小姐', 'ojou-sama', TagType.none),
    HanimeTag('偶像', 'idol', TagType.none),
    HanimeTag('女僕', 'maid', TagType.none),
    HanimeTag('巫女', 'shrine_maiden', TagType.none),
    HanimeTag('魔女', 'witch', TagType.none),
    HanimeTag('修女', 'nun', TagType.none),
    HanimeTag('風俗娘', 'sex_worker', TagType.none),
    HanimeTag('公主', 'princess', TagType.none),
    HanimeTag('女忍者', 'kunoichi', TagType.none),
    HanimeTag('女戰士', 'female_warrior', TagType.none),
    HanimeTag('女騎士', 'female_knight', TagType.none),
    HanimeTag('魔法少女', 'magical_girl', TagType.none),
    HanimeTag('異種族', 'nonhuman', TagType.none),
    HanimeTag('天使', 'angel', TagType.none),
    HanimeTag('妖精', 'fairy', TagType.none),
    HanimeTag('魔物娘', 'monster_girl', TagType.none),
    HanimeTag('魅魔', 'succubus', TagType.none),
    HanimeTag('吸血鬼', 'vampire', TagType.none),
    HanimeTag('女鬼', 'ghost_girl', TagType.none),
    HanimeTag('獸娘', 'animal_girl', TagType.none),
    HanimeTag('福瑞', 'furry', TagType.none),
    HanimeTag('乳牛', 'hucow', TagType.none),
    HanimeTag('機械娘', 'robot_girl', TagType.none),
    HanimeTag('碧池', 'bitch', TagType.none),
    HanimeTag('痴女', 'nympho', TagType.none),
    HanimeTag('雌小鬼', 'mesugaki', TagType.none),
    HanimeTag('不良少女', 'delinquent_girl', TagType.none),
    HanimeTag('傲嬌', 'tsundere', TagType.none),
    HanimeTag('病嬌', 'yandere', TagType.none),
    HanimeTag('無口', 'quiet_girl', TagType.none),
    HanimeTag('無表情', 'expressionless', TagType.none),
    HanimeTag('眼神死', 'dead_eyes', TagType.none),
    HanimeTag('正太', 'shota', TagType.none),
    HanimeTag('偽娘', 'crossdresser', TagType.none),
    HanimeTag('扶他', 'futanari', TagType.none),
    // ── 外貌身材 · appearance ──
    HanimeTag('短髮', 'short_hair', TagType.none),
    HanimeTag('馬尾', 'ponytail', TagType.none),
    HanimeTag('雙馬尾', 'twintails', TagType.none),
    HanimeTag('丸子頭', 'hair_bun', TagType.none),
    HanimeTag('巨乳', 'big_breasts', TagType.none),
    HanimeTag('乳環', 'nipple_piercing', TagType.none),
    HanimeTag('舌環', 'tongue_piercing', TagType.none),
    HanimeTag('貧乳', 'flat_chest', TagType.none),
    HanimeTag('黑皮膚', 'dark_skin', TagType.none),
    HanimeTag('曬痕', 'tan_lines', TagType.none),
    HanimeTag('眼鏡娘', 'glasses', TagType.none),
    HanimeTag('獸耳', 'animal_ears', TagType.none),
    HanimeTag('尖耳朵', 'pointy_ears', TagType.none),
    HanimeTag('異色瞳', 'heterochromia', TagType.none),
    HanimeTag('美人痣', 'beauty_mark', TagType.none),
    HanimeTag('肌肉女', 'muscular_female', TagType.none),
    HanimeTag('白虎', 'shaved_pussy', TagType.none),
    HanimeTag('陰毛', 'pubic_hair', TagType.none),
    HanimeTag('腋毛', 'armpit_hair', TagType.none),
    HanimeTag('大屌', 'big_penis', TagType.none),
    HanimeTag('黑屌', 'dark_penis', TagType.none),
    HanimeTag('著衣', 'clothed_sex', TagType.none),
    HanimeTag('水手服', 'sailor_uniform', TagType.none),
    HanimeTag('體操服', 'gym_uniform', TagType.none),
    HanimeTag('泳裝', 'swimsuit', TagType.none),
    HanimeTag('比基尼', 'bikini', TagType.none),
    HanimeTag('死庫水', 'school_swimsuit', TagType.none),
    HanimeTag('和服', 'kimono', TagType.none),
    HanimeTag('兔女郎', 'bunny_girl', TagType.none),
    HanimeTag('圍裙', 'apron', TagType.none),
    HanimeTag('啦啦隊', 'cheerleader', TagType.none),
    HanimeTag('絲襪', 'stockings', TagType.none),
    HanimeTag('吊襪帶', 'garter_belt', TagType.none),
    HanimeTag('熱褲', 'hot_pants', TagType.none),
    HanimeTag('迷你裙', 'miniskirt', TagType.none),
    HanimeTag('性感內衣', 'lingerie', TagType.none),
    HanimeTag('緊身衣', 'bodysuit', TagType.none),
    HanimeTag('丁字褲', 'thong', TagType.none),
    HanimeTag('高跟鞋', 'high_heels', TagType.none),
    HanimeTag('睡衣', 'pajamas', TagType.none),
    HanimeTag('婚紗', 'wedding_dress', TagType.none),
    HanimeTag('旗袍', 'china_dress', TagType.none),
    HanimeTag('古裝', 'traditional_clothes', TagType.none),
    HanimeTag('哥德', 'gothic', TagType.none),
    HanimeTag('口罩', 'face_mask', TagType.none),
    HanimeTag('刺青', 'tattoo', TagType.none),
    HanimeTag('淫紋', 'womb_tattoo', TagType.none),
    HanimeTag('身體寫字', 'body_writing', TagType.none),
    // ── 情境場所 · settings ──
    HanimeTag('校園', 'school', TagType.none),
    HanimeTag('教室', 'classroom', TagType.none),
    HanimeTag('圖書館', 'library', TagType.none),
    HanimeTag('保健室', 'infirmary', TagType.none),
    HanimeTag('體育倉庫', 'gym_storage', TagType.none),
    HanimeTag('游泳池', 'pool', TagType.none),
    HanimeTag('愛情賓館', 'love_hotel', TagType.none),
    HanimeTag('醫院', 'hospital', TagType.none),
    HanimeTag('辦公室', 'office', TagType.none),
    HanimeTag('浴室', 'bathroom', TagType.none),
    HanimeTag('窗邊', 'window', TagType.none),
    HanimeTag('公共廁所', 'public_toilet', TagType.none),
    HanimeTag('公眾場合', 'public', TagType.none),
    HanimeTag('戶外野戰', 'outdoor_sex', TagType.none),
    HanimeTag('電車', 'train', TagType.none),
    HanimeTag('車震', 'car_sex', TagType.none),
    HanimeTag('遊艇', 'yacht', TagType.none),
    HanimeTag('露營帳篷', 'tent', TagType.none),
    HanimeTag('電影院', 'cinema', TagType.none),
    HanimeTag('健身房', 'gym', TagType.none),
    HanimeTag('沙灘', 'beach', TagType.none),
    HanimeTag('溫泉', 'hot_spring', TagType.none),
    HanimeTag('夜店', 'nightclub', TagType.none),
    HanimeTag('監獄', 'prison', TagType.none),
    HanimeTag('教堂', 'church', TagType.none),
    // ── 故事劇情 · story ──
    HanimeTag('純愛', 'vanilla', TagType.none),
    HanimeTag('戀愛喜劇', 'romcom', TagType.none),
    HanimeTag('後宮', 'harem', TagType.none),
    HanimeTag('十指緊扣', 'hand_holding', TagType.none),
    HanimeTag('開大車', 'hardcore_plot', TagType.none),
    HanimeTag('NTR', 'ntr', TagType.none),
    HanimeTag('精神控制', 'mind_control', TagType.none),
    HanimeTag('藥物', 'drugs', TagType.none),
    HanimeTag('痴漢', 'chikan', TagType.none),
    HanimeTag('阿嘿顏', 'ahegao', TagType.none),
    HanimeTag('哭泣', 'crying', TagType.none),
    HanimeTag('精神崩潰', 'mind_break', TagType.none),
    HanimeTag('獵奇', 'guro', TagType.none),
    HanimeTag('BDSM', 'bdsm', TagType.none),
    HanimeTag('綑綁', 'bondage', TagType.none),
    HanimeTag('眼罩', 'blindfold', TagType.none),
    HanimeTag('項圈', 'collar', TagType.none),
    HanimeTag('調教', 'training', TagType.none),
    HanimeTag('異物插入', 'object_insertion', TagType.none),
    HanimeTag('尋歡洞', 'glory_hole', TagType.none),
    HanimeTag('肉便器', 'cum_dump', TagType.none),
    HanimeTag('性奴隸', 'sex_slave', TagType.none),
    HanimeTag('胃凸', 'stomach_bulge', TagType.none),
    HanimeTag('強制', 'forced', TagType.none),
    HanimeTag('輪姦', 'gang_rape', TagType.none),
    HanimeTag('凌辱', 'humiliation', TagType.none),
    HanimeTag('性暴力', 'sexual_violence', TagType.none),
    HanimeTag('逆強制', 'reverse_rape', TagType.none),
    HanimeTag('女王樣', 'dominatrix', TagType.none),
    HanimeTag('榨精', 'milking', TagType.none),
    HanimeTag('母女丼', 'mother_daughter_threesome', TagType.none),
    HanimeTag('姐妹丼', 'sisters_threesome', TagType.none),
    HanimeTag('出軌', 'cheating', TagType.none),
    HanimeTag('醉酒', 'drunk', TagType.none),
    HanimeTag('攝影', 'filming', TagType.none),
    HanimeTag('睡眠姦', 'sleep_sex', TagType.none),
    HanimeTag('機械姦', 'machine_sex', TagType.none),
    HanimeTag('蟲姦', 'insect_sex', TagType.none),
    HanimeTag('性轉換', 'gender_swap', TagType.none),
    HanimeTag('百合', 'yuri', TagType.none),
    HanimeTag('耽美', 'yaoi', TagType.none),
    HanimeTag('時間停止', 'time_stop', TagType.none),
    HanimeTag('異世界', 'isekai', TagType.none),
    HanimeTag('怪獸', 'monster', TagType.none),
    HanimeTag('哥布林', 'goblin', TagType.none),
    HanimeTag('世界末日', 'apocalypse', TagType.none),
    // ── 性交體位 · acts ──
    HanimeTag('手交', 'handjob', TagType.none),
    HanimeTag('指交', 'fingering', TagType.none),
    HanimeTag('玩乳頭', 'nipple_play', TagType.none),
    HanimeTag('乳交', 'titfuck', TagType.none),
    HanimeTag('乳頭交', 'nipple_fuck', TagType.none),
    HanimeTag('肛交', 'anal', TagType.none),
    HanimeTag('雙洞齊下', 'double_penetration', TagType.none),
    HanimeTag('腳交', 'footjob', TagType.none),
    HanimeTag('素股', 'thigh_sex', TagType.none),
    HanimeTag('拳交', 'fisting', TagType.none),
    HanimeTag('3P', 'threesome', TagType.none),
    HanimeTag('群交', 'group_sex', TagType.none),
    HanimeTag('口交', 'blowjob', TagType.none),
    HanimeTag('跪舔', 'kneeling_blowjob', TagType.none),
    HanimeTag('深喉嚨', 'deepthroat', TagType.none),
    HanimeTag('口爆', 'cum_in_mouth', TagType.none),
    HanimeTag('吞精', 'swallowing', TagType.none),
    HanimeTag('舔蛋蛋', 'ball_licking', TagType.none),
    HanimeTag('舔穴', 'cunnilingus', TagType.none),
    HanimeTag('69', '69', TagType.none),
    HanimeTag('自慰', 'masturbation', TagType.none),
    HanimeTag('腋交', 'armpit_sex', TagType.none),
    HanimeTag('舔腋下', 'armpit_licking', TagType.none),
    HanimeTag('髮交', 'hairjob', TagType.none),
    HanimeTag('舔耳朵', 'ear_licking', TagType.none),
    HanimeTag('舔腳', 'foot_licking', TagType.none),
    HanimeTag('內射', 'creampie', TagType.none),
    HanimeTag('外射', 'cum_outside', TagType.none),
    HanimeTag('顏射', 'facial', TagType.none),
    HanimeTag('潮吹', 'squirting', TagType.none),
    HanimeTag('懷孕', 'pregnant', TagType.none),
    HanimeTag('噴奶', 'lactation', TagType.none),
    HanimeTag('放尿', 'peeing', TagType.none),
    HanimeTag('排便', 'scat', TagType.none),
    HanimeTag('騎乘位', 'cowgirl_position', TagType.none),
    HanimeTag('背後位', 'doggy_style', TagType.none),
    HanimeTag('側面位', 'spooning', TagType.none),
    HanimeTag('顏面騎乘', 'facesitting', TagType.none),
    HanimeTag('火車便當', 'suspended_congress', TagType.none),
    HanimeTag('一字馬', 'standing_split', TagType.none),
    HanimeTag('性玩具', 'sex_toys', TagType.none),
    HanimeTag('飛機杯', 'onahole', TagType.none),
    HanimeTag('跳蛋', 'egg_vibrator', TagType.none),
    HanimeTag('毒龍鑽', 'rimming', TagType.none),
    HanimeTag('觸手', 'tentacles', TagType.none),
    HanimeTag('獸交', 'bestiality', TagType.none),
    HanimeTag('頸手枷', 'stocks', TagType.none),
    HanimeTag('扯頭髮', 'hair_pulling', TagType.none),
    HanimeTag('掐脖子', 'choking', TagType.none),
    HanimeTag('打屁股', 'spanking', TagType.none),
    HanimeTag('肉棒打臉', 'cock_slap', TagType.none),
    HanimeTag('陰道外翻', 'prolapse', TagType.none),
    HanimeTag('男乳首責', 'male_nipple_play', TagType.none),
    HanimeTag('接吻', 'kissing', TagType.none),
    HanimeTag('舌吻', 'french_kiss', TagType.none),
    HanimeTag('POV', 'pov', TagType.none),
  ];

  /// Video categories (`genre=` — verified working values only).
  static const Map<String, String> genres = {
    'hentai': '裏番',
    'shorts': '泡麵番',
    'motion_anime': 'Motion Anime',
    '3dcg': '3DCG',
    '2.5d': '2.5D',
    '2d': '2D動畫',
    'ai': 'AI生成',
    'mmd': 'MMD',
    'cosplay': 'Cosplay',
  };

  /// Sort orders (`sort=` — every value verified to change the result set;
  /// `newest` is the default ordering).
  static const Map<String, String> sorts = {
    'newest': '最新上市',
    'latest_upload': '最新上傳',
    'daily': '本日排行',
    'weekly': '本週排行',
    'monthly': '本月排行',
    'views': '觀看次數',
    'trending': '他們在看',
  };

  static final Map<String, HanimeTag> _byZh = {for (final t in tags) t.zh: t};
  static final Map<String, HanimeTag> _byEn = {for (final t in tags) t.en: t};

  /// English token for a site tag; null when the site added a tag this
  /// dictionary has not caught up with (shown as-is in that case).
  static HanimeTag? fromZh(String zh) => _byZh[zh.trim()];

  /// Site tag for an English token typed by the user.
  static HanimeTag? fromEn(String en) => _byEn[en.trim().toLowerCase()];

  /// Dictionary entries matching a partial query in either language.
  static List<HanimeTag> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final t in tags)
        if (t.en.contains(q) || t.zh.contains(query.trim())) t,
    ];
  }
}
