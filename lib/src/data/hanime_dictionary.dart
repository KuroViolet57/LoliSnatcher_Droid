import 'package:lolisnatcher/src/data/tag_type.dart';

/// The seven groups the site's search form lists its tags under, in the
/// form's order. The Tag builder shows one chip per group.
enum HanimeGroup {
  attribute('attribute', 'Attributes'),
  relationship('relationship', 'Relationships'),
  archetype('archetype', 'Archetypes'),
  appearance('appearance', 'Appearance'),
  setting('setting', 'Settings'),
  story('story', 'Story'),
  act('act', 'Acts');

  const HanimeGroup(this.key, this.label);

  /// The namespace key rows are filed under in the tag snapshot.
  final String key;
  final String label;

  static HanimeGroup? byKey(String key) {
    for (final g in values) {
      if (g.key == key) return g;
    }
    return null;
  }
}

class HanimeTag {
  const HanimeTag(this.zh, this.en, this.type, this.group);

  /// The exact string the site uses in `tags[]`.
  final String zh;

  /// Booru-style English token (underscored, lowercase).
  final String en;

  final TagType type;

  /// The search-form group the site lists the tag under.
  final HanimeGroup group;
}

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
class HanimeDictionary {
  HanimeDictionary._();

  /// group 影片屬性 (video attributes) -> meta; everything else is a normal
  /// descriptive tag. The "character" entries are archetypes (maid, nurse),
  /// not named characters, so they stay general like on any booru.
  static const List<HanimeTag> tags = [
    // ── 影片屬性 · video attributes ──
    HanimeTag('無碼', 'uncensored', TagType.meta, HanimeGroup.attribute),
    HanimeTag('AI解碼', 'ai_decensored', TagType.meta, HanimeGroup.attribute),
    HanimeTag('中文字幕', 'chinese_subtitles', TagType.meta, HanimeGroup.attribute),
    HanimeTag('中文配音', 'chinese_dub', TagType.meta, HanimeGroup.attribute),
    HanimeTag('同人作品', 'doujin', TagType.meta, HanimeGroup.attribute),
    HanimeTag('斷面圖', 'cross_section', TagType.meta, HanimeGroup.attribute),
    HanimeTag('ASMR', 'asmr', TagType.meta, HanimeGroup.attribute),
    HanimeTag('1080p', '1080p', TagType.meta, HanimeGroup.attribute),
    HanimeTag('60FPS', '60fps', TagType.meta, HanimeGroup.attribute),
    // ── 人物關係 · relationships ──
    HanimeTag('近親', 'incest', TagType.none, HanimeGroup.relationship),
    HanimeTag('姐', 'older_sister', TagType.none, HanimeGroup.relationship),
    HanimeTag('妹', 'younger_sister', TagType.none, HanimeGroup.relationship),
    HanimeTag('母', 'mother', TagType.none, HanimeGroup.relationship),
    HanimeTag('女兒', 'daughter', TagType.none, HanimeGroup.relationship),
    HanimeTag('師生', 'teacher_and_student', TagType.none, HanimeGroup.relationship),
    HanimeTag('情侶', 'couple', TagType.none, HanimeGroup.relationship),
    HanimeTag('青梅竹馬', 'childhood_friend', TagType.none, HanimeGroup.relationship),
    HanimeTag('同事', 'coworker', TagType.none, HanimeGroup.relationship),
    // ── 角色設定 · character archetypes ──
    HanimeTag('JK', 'schoolgirl', TagType.none, HanimeGroup.archetype),
    HanimeTag('處女', 'virgin', TagType.none, HanimeGroup.archetype),
    HanimeTag('御姐', 'onee-san', TagType.none, HanimeGroup.archetype),
    HanimeTag('熟女', 'milf', TagType.none, HanimeGroup.archetype),
    HanimeTag('人妻', 'married_woman', TagType.none, HanimeGroup.archetype),
    HanimeTag('女教師', 'female_teacher', TagType.none, HanimeGroup.archetype),
    HanimeTag('男教師', 'male_teacher', TagType.none, HanimeGroup.archetype),
    HanimeTag('女醫生', 'female_doctor', TagType.none, HanimeGroup.archetype),
    HanimeTag('女病人', 'female_patient', TagType.none, HanimeGroup.archetype),
    HanimeTag('護士', 'nurse', TagType.none, HanimeGroup.archetype),
    HanimeTag('OL', 'office_lady', TagType.none, HanimeGroup.archetype),
    HanimeTag('女警', 'policewoman', TagType.none, HanimeGroup.archetype),
    HanimeTag('大小姐', 'ojou-sama', TagType.none, HanimeGroup.archetype),
    HanimeTag('偶像', 'idol', TagType.none, HanimeGroup.archetype),
    HanimeTag('女僕', 'maid', TagType.none, HanimeGroup.archetype),
    HanimeTag('巫女', 'shrine_maiden', TagType.none, HanimeGroup.archetype),
    HanimeTag('魔女', 'witch', TagType.none, HanimeGroup.archetype),
    HanimeTag('修女', 'nun', TagType.none, HanimeGroup.archetype),
    HanimeTag('風俗娘', 'sex_worker', TagType.none, HanimeGroup.archetype),
    HanimeTag('公主', 'princess', TagType.none, HanimeGroup.archetype),
    HanimeTag('女忍者', 'kunoichi', TagType.none, HanimeGroup.archetype),
    HanimeTag('女戰士', 'female_warrior', TagType.none, HanimeGroup.archetype),
    HanimeTag('女騎士', 'female_knight', TagType.none, HanimeGroup.archetype),
    HanimeTag('魔法少女', 'magical_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('異種族', 'nonhuman', TagType.none, HanimeGroup.archetype),
    HanimeTag('天使', 'angel', TagType.none, HanimeGroup.archetype),
    HanimeTag('妖精', 'fairy', TagType.none, HanimeGroup.archetype),
    HanimeTag('魔物娘', 'monster_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('魅魔', 'succubus', TagType.none, HanimeGroup.archetype),
    HanimeTag('吸血鬼', 'vampire', TagType.none, HanimeGroup.archetype),
    HanimeTag('女鬼', 'ghost_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('獸娘', 'animal_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('福瑞', 'furry', TagType.none, HanimeGroup.archetype),
    HanimeTag('乳牛', 'hucow', TagType.none, HanimeGroup.archetype),
    HanimeTag('機械娘', 'robot_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('碧池', 'bitch', TagType.none, HanimeGroup.archetype),
    HanimeTag('痴女', 'nympho', TagType.none, HanimeGroup.archetype),
    HanimeTag('雌小鬼', 'mesugaki', TagType.none, HanimeGroup.archetype),
    HanimeTag('不良少女', 'delinquent_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('傲嬌', 'tsundere', TagType.none, HanimeGroup.archetype),
    HanimeTag('病嬌', 'yandere', TagType.none, HanimeGroup.archetype),
    HanimeTag('無口', 'quiet_girl', TagType.none, HanimeGroup.archetype),
    HanimeTag('無表情', 'expressionless', TagType.none, HanimeGroup.archetype),
    HanimeTag('眼神死', 'dead_eyes', TagType.none, HanimeGroup.archetype),
    HanimeTag('正太', 'shota', TagType.none, HanimeGroup.archetype),
    HanimeTag('偽娘', 'crossdresser', TagType.none, HanimeGroup.archetype),
    HanimeTag('扶他', 'futanari', TagType.none, HanimeGroup.archetype),
    // ── 外貌身材 · appearance ──
    HanimeTag('短髮', 'short_hair', TagType.none, HanimeGroup.appearance),
    HanimeTag('馬尾', 'ponytail', TagType.none, HanimeGroup.appearance),
    HanimeTag('雙馬尾', 'twintails', TagType.none, HanimeGroup.appearance),
    HanimeTag('丸子頭', 'hair_bun', TagType.none, HanimeGroup.appearance),
    HanimeTag('巨乳', 'big_breasts', TagType.none, HanimeGroup.appearance),
    HanimeTag('乳環', 'nipple_piercing', TagType.none, HanimeGroup.appearance),
    HanimeTag('舌環', 'tongue_piercing', TagType.none, HanimeGroup.appearance),
    HanimeTag('貧乳', 'flat_chest', TagType.none, HanimeGroup.appearance),
    HanimeTag('黑皮膚', 'dark_skin', TagType.none, HanimeGroup.appearance),
    HanimeTag('曬痕', 'tan_lines', TagType.none, HanimeGroup.appearance),
    HanimeTag('眼鏡娘', 'glasses', TagType.none, HanimeGroup.appearance),
    HanimeTag('獸耳', 'animal_ears', TagType.none, HanimeGroup.appearance),
    HanimeTag('尖耳朵', 'pointy_ears', TagType.none, HanimeGroup.appearance),
    HanimeTag('異色瞳', 'heterochromia', TagType.none, HanimeGroup.appearance),
    HanimeTag('美人痣', 'beauty_mark', TagType.none, HanimeGroup.appearance),
    HanimeTag('肌肉女', 'muscular_female', TagType.none, HanimeGroup.appearance),
    HanimeTag('白虎', 'shaved_pussy', TagType.none, HanimeGroup.appearance),
    HanimeTag('陰毛', 'pubic_hair', TagType.none, HanimeGroup.appearance),
    HanimeTag('腋毛', 'armpit_hair', TagType.none, HanimeGroup.appearance),
    HanimeTag('大屌', 'big_penis', TagType.none, HanimeGroup.appearance),
    HanimeTag('黑屌', 'dark_penis', TagType.none, HanimeGroup.appearance),
    HanimeTag('著衣', 'clothed_sex', TagType.none, HanimeGroup.appearance),
    HanimeTag('水手服', 'sailor_uniform', TagType.none, HanimeGroup.appearance),
    HanimeTag('體操服', 'gym_uniform', TagType.none, HanimeGroup.appearance),
    HanimeTag('泳裝', 'swimsuit', TagType.none, HanimeGroup.appearance),
    HanimeTag('比基尼', 'bikini', TagType.none, HanimeGroup.appearance),
    HanimeTag('死庫水', 'school_swimsuit', TagType.none, HanimeGroup.appearance),
    HanimeTag('和服', 'kimono', TagType.none, HanimeGroup.appearance),
    HanimeTag('兔女郎', 'bunny_girl', TagType.none, HanimeGroup.appearance),
    HanimeTag('圍裙', 'apron', TagType.none, HanimeGroup.appearance),
    HanimeTag('啦啦隊', 'cheerleader', TagType.none, HanimeGroup.appearance),
    HanimeTag('絲襪', 'stockings', TagType.none, HanimeGroup.appearance),
    HanimeTag('吊襪帶', 'garter_belt', TagType.none, HanimeGroup.appearance),
    HanimeTag('熱褲', 'hot_pants', TagType.none, HanimeGroup.appearance),
    HanimeTag('迷你裙', 'miniskirt', TagType.none, HanimeGroup.appearance),
    HanimeTag('性感內衣', 'lingerie', TagType.none, HanimeGroup.appearance),
    HanimeTag('緊身衣', 'bodysuit', TagType.none, HanimeGroup.appearance),
    HanimeTag('丁字褲', 'thong', TagType.none, HanimeGroup.appearance),
    HanimeTag('高跟鞋', 'high_heels', TagType.none, HanimeGroup.appearance),
    HanimeTag('睡衣', 'pajamas', TagType.none, HanimeGroup.appearance),
    HanimeTag('婚紗', 'wedding_dress', TagType.none, HanimeGroup.appearance),
    HanimeTag('旗袍', 'china_dress', TagType.none, HanimeGroup.appearance),
    HanimeTag('古裝', 'traditional_clothes', TagType.none, HanimeGroup.appearance),
    HanimeTag('哥德', 'gothic', TagType.none, HanimeGroup.appearance),
    HanimeTag('口罩', 'face_mask', TagType.none, HanimeGroup.appearance),
    HanimeTag('刺青', 'tattoo', TagType.none, HanimeGroup.appearance),
    HanimeTag('淫紋', 'womb_tattoo', TagType.none, HanimeGroup.appearance),
    HanimeTag('身體寫字', 'body_writing', TagType.none, HanimeGroup.appearance),
    // ── 情境場所 · settings ──
    HanimeTag('校園', 'school', TagType.none, HanimeGroup.setting),
    HanimeTag('教室', 'classroom', TagType.none, HanimeGroup.setting),
    HanimeTag('圖書館', 'library', TagType.none, HanimeGroup.setting),
    HanimeTag('保健室', 'infirmary', TagType.none, HanimeGroup.setting),
    HanimeTag('體育倉庫', 'gym_storage', TagType.none, HanimeGroup.setting),
    HanimeTag('游泳池', 'pool', TagType.none, HanimeGroup.setting),
    HanimeTag('愛情賓館', 'love_hotel', TagType.none, HanimeGroup.setting),
    HanimeTag('醫院', 'hospital', TagType.none, HanimeGroup.setting),
    HanimeTag('辦公室', 'office', TagType.none, HanimeGroup.setting),
    HanimeTag('浴室', 'bathroom', TagType.none, HanimeGroup.setting),
    HanimeTag('窗邊', 'window', TagType.none, HanimeGroup.setting),
    HanimeTag('公共廁所', 'public_toilet', TagType.none, HanimeGroup.setting),
    HanimeTag('公眾場合', 'public', TagType.none, HanimeGroup.setting),
    HanimeTag('戶外野戰', 'outdoor_sex', TagType.none, HanimeGroup.setting),
    HanimeTag('電車', 'train', TagType.none, HanimeGroup.setting),
    HanimeTag('車震', 'car_sex', TagType.none, HanimeGroup.setting),
    HanimeTag('遊艇', 'yacht', TagType.none, HanimeGroup.setting),
    HanimeTag('露營帳篷', 'tent', TagType.none, HanimeGroup.setting),
    HanimeTag('電影院', 'cinema', TagType.none, HanimeGroup.setting),
    HanimeTag('健身房', 'gym', TagType.none, HanimeGroup.setting),
    HanimeTag('沙灘', 'beach', TagType.none, HanimeGroup.setting),
    HanimeTag('溫泉', 'hot_spring', TagType.none, HanimeGroup.setting),
    HanimeTag('夜店', 'nightclub', TagType.none, HanimeGroup.setting),
    HanimeTag('監獄', 'prison', TagType.none, HanimeGroup.setting),
    HanimeTag('教堂', 'church', TagType.none, HanimeGroup.setting),
    // ── 故事劇情 · story ──
    HanimeTag('純愛', 'vanilla', TagType.none, HanimeGroup.story),
    HanimeTag('戀愛喜劇', 'romcom', TagType.none, HanimeGroup.story),
    HanimeTag('後宮', 'harem', TagType.none, HanimeGroup.story),
    HanimeTag('十指緊扣', 'hand_holding', TagType.none, HanimeGroup.story),
    HanimeTag('開大車', 'hardcore_plot', TagType.none, HanimeGroup.story),
    HanimeTag('NTR', 'ntr', TagType.none, HanimeGroup.story),
    HanimeTag('精神控制', 'mind_control', TagType.none, HanimeGroup.story),
    HanimeTag('藥物', 'drugs', TagType.none, HanimeGroup.story),
    HanimeTag('痴漢', 'chikan', TagType.none, HanimeGroup.story),
    HanimeTag('阿嘿顏', 'ahegao', TagType.none, HanimeGroup.story),
    HanimeTag('哭泣', 'crying', TagType.none, HanimeGroup.story),
    HanimeTag('精神崩潰', 'mind_break', TagType.none, HanimeGroup.story),
    HanimeTag('獵奇', 'guro', TagType.none, HanimeGroup.story),
    HanimeTag('BDSM', 'bdsm', TagType.none, HanimeGroup.story),
    HanimeTag('綑綁', 'bondage', TagType.none, HanimeGroup.story),
    HanimeTag('眼罩', 'blindfold', TagType.none, HanimeGroup.story),
    HanimeTag('項圈', 'collar', TagType.none, HanimeGroup.story),
    HanimeTag('調教', 'training', TagType.none, HanimeGroup.story),
    HanimeTag('異物插入', 'object_insertion', TagType.none, HanimeGroup.story),
    HanimeTag('尋歡洞', 'glory_hole', TagType.none, HanimeGroup.story),
    HanimeTag('肉便器', 'cum_dump', TagType.none, HanimeGroup.story),
    HanimeTag('性奴隸', 'sex_slave', TagType.none, HanimeGroup.story),
    HanimeTag('胃凸', 'stomach_bulge', TagType.none, HanimeGroup.story),
    HanimeTag('強制', 'forced', TagType.none, HanimeGroup.story),
    HanimeTag('輪姦', 'gang_rape', TagType.none, HanimeGroup.story),
    HanimeTag('凌辱', 'humiliation', TagType.none, HanimeGroup.story),
    HanimeTag('性暴力', 'sexual_violence', TagType.none, HanimeGroup.story),
    HanimeTag('逆強制', 'reverse_rape', TagType.none, HanimeGroup.story),
    HanimeTag('女王樣', 'dominatrix', TagType.none, HanimeGroup.story),
    HanimeTag('榨精', 'milking', TagType.none, HanimeGroup.story),
    HanimeTag('母女丼', 'mother_daughter_threesome', TagType.none, HanimeGroup.story),
    HanimeTag('姐妹丼', 'sisters_threesome', TagType.none, HanimeGroup.story),
    HanimeTag('出軌', 'cheating', TagType.none, HanimeGroup.story),
    HanimeTag('醉酒', 'drunk', TagType.none, HanimeGroup.story),
    HanimeTag('攝影', 'filming', TagType.none, HanimeGroup.story),
    HanimeTag('睡眠姦', 'sleep_sex', TagType.none, HanimeGroup.story),
    HanimeTag('機械姦', 'machine_sex', TagType.none, HanimeGroup.story),
    HanimeTag('蟲姦', 'insect_sex', TagType.none, HanimeGroup.story),
    HanimeTag('性轉換', 'gender_swap', TagType.none, HanimeGroup.story),
    HanimeTag('百合', 'yuri', TagType.none, HanimeGroup.story),
    HanimeTag('耽美', 'yaoi', TagType.none, HanimeGroup.story),
    HanimeTag('時間停止', 'time_stop', TagType.none, HanimeGroup.story),
    HanimeTag('異世界', 'isekai', TagType.none, HanimeGroup.story),
    HanimeTag('怪獸', 'monster', TagType.none, HanimeGroup.story),
    HanimeTag('哥布林', 'goblin', TagType.none, HanimeGroup.story),
    HanimeTag('世界末日', 'apocalypse', TagType.none, HanimeGroup.story),
    // ── 性交體位 · acts ──
    HanimeTag('手交', 'handjob', TagType.none, HanimeGroup.act),
    HanimeTag('指交', 'fingering', TagType.none, HanimeGroup.act),
    HanimeTag('玩乳頭', 'nipple_play', TagType.none, HanimeGroup.act),
    HanimeTag('乳交', 'titfuck', TagType.none, HanimeGroup.act),
    HanimeTag('乳頭交', 'nipple_fuck', TagType.none, HanimeGroup.act),
    HanimeTag('肛交', 'anal', TagType.none, HanimeGroup.act),
    HanimeTag('雙洞齊下', 'double_penetration', TagType.none, HanimeGroup.act),
    HanimeTag('腳交', 'footjob', TagType.none, HanimeGroup.act),
    HanimeTag('素股', 'thigh_sex', TagType.none, HanimeGroup.act),
    HanimeTag('拳交', 'fisting', TagType.none, HanimeGroup.act),
    HanimeTag('3P', 'threesome', TagType.none, HanimeGroup.act),
    HanimeTag('群交', 'group_sex', TagType.none, HanimeGroup.act),
    HanimeTag('口交', 'blowjob', TagType.none, HanimeGroup.act),
    HanimeTag('跪舔', 'kneeling_blowjob', TagType.none, HanimeGroup.act),
    HanimeTag('深喉嚨', 'deepthroat', TagType.none, HanimeGroup.act),
    HanimeTag('口爆', 'cum_in_mouth', TagType.none, HanimeGroup.act),
    HanimeTag('吞精', 'swallowing', TagType.none, HanimeGroup.act),
    HanimeTag('舔蛋蛋', 'ball_licking', TagType.none, HanimeGroup.act),
    HanimeTag('舔穴', 'cunnilingus', TagType.none, HanimeGroup.act),
    HanimeTag('69', '69', TagType.none, HanimeGroup.act),
    HanimeTag('自慰', 'masturbation', TagType.none, HanimeGroup.act),
    HanimeTag('腋交', 'armpit_sex', TagType.none, HanimeGroup.act),
    HanimeTag('舔腋下', 'armpit_licking', TagType.none, HanimeGroup.act),
    HanimeTag('髮交', 'hairjob', TagType.none, HanimeGroup.act),
    HanimeTag('舔耳朵', 'ear_licking', TagType.none, HanimeGroup.act),
    HanimeTag('舔腳', 'foot_licking', TagType.none, HanimeGroup.act),
    HanimeTag('內射', 'creampie', TagType.none, HanimeGroup.act),
    HanimeTag('外射', 'cum_outside', TagType.none, HanimeGroup.act),
    HanimeTag('顏射', 'facial', TagType.none, HanimeGroup.act),
    HanimeTag('潮吹', 'squirting', TagType.none, HanimeGroup.act),
    HanimeTag('懷孕', 'pregnant', TagType.none, HanimeGroup.act),
    HanimeTag('噴奶', 'lactation', TagType.none, HanimeGroup.act),
    HanimeTag('放尿', 'peeing', TagType.none, HanimeGroup.act),
    HanimeTag('排便', 'scat', TagType.none, HanimeGroup.act),
    HanimeTag('騎乘位', 'cowgirl_position', TagType.none, HanimeGroup.act),
    HanimeTag('背後位', 'doggy_style', TagType.none, HanimeGroup.act),
    HanimeTag('側面位', 'spooning', TagType.none, HanimeGroup.act),
    HanimeTag('顏面騎乘', 'facesitting', TagType.none, HanimeGroup.act),
    HanimeTag('火車便當', 'suspended_congress', TagType.none, HanimeGroup.act),
    HanimeTag('一字馬', 'standing_split', TagType.none, HanimeGroup.act),
    HanimeTag('性玩具', 'sex_toys', TagType.none, HanimeGroup.act),
    HanimeTag('飛機杯', 'onahole', TagType.none, HanimeGroup.act),
    HanimeTag('跳蛋', 'egg_vibrator', TagType.none, HanimeGroup.act),
    HanimeTag('毒龍鑽', 'rimming', TagType.none, HanimeGroup.act),
    HanimeTag('觸手', 'tentacles', TagType.none, HanimeGroup.act),
    HanimeTag('獸交', 'bestiality', TagType.none, HanimeGroup.act),
    HanimeTag('頸手枷', 'stocks', TagType.none, HanimeGroup.act),
    HanimeTag('扯頭髮', 'hair_pulling', TagType.none, HanimeGroup.act),
    HanimeTag('掐脖子', 'choking', TagType.none, HanimeGroup.act),
    HanimeTag('打屁股', 'spanking', TagType.none, HanimeGroup.act),
    HanimeTag('肉棒打臉', 'cock_slap', TagType.none, HanimeGroup.act),
    HanimeTag('陰道外翻', 'prolapse', TagType.none, HanimeGroup.act),
    HanimeTag('男乳首責', 'male_nipple_play', TagType.none, HanimeGroup.act),
    HanimeTag('接吻', 'kissing', TagType.none, HanimeGroup.act),
    HanimeTag('舌吻', 'french_kiss', TagType.none, HanimeGroup.act),
    HanimeTag('POV', 'pov', TagType.none, HanimeGroup.act),
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

  /// The tags of one search-form group, in the form's order.
  static List<HanimeTag> byGroup(HanimeGroup group) => [
    for (final t in tags)
      if (t.group == group) t,
  ];

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
