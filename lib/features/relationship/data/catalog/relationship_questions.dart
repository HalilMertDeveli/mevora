enum RelationshipTopic {
  jealousy,
  trust,
  loyalty,
  communication,
  boundaries,
  socialLife,
  friendship,
  personalSpace,
  futurePlans,
  money,
  flirting,
  exes,
  expectations,
}

class RelationshipAnswerOption {
  const RelationshipAnswerOption({
    required this.id,
    required this.labelEn,
    required this.labelTr,
  });

  final String id;
  final String labelEn;
  final String labelTr;

  String labelFor(String languageCode) {
    return languageCode == 'tr' ? labelTr : labelEn;
  }
}

class RelationshipQuestion {
  const RelationshipQuestion({
    required this.id,
    required this.topic,
    required this.promptEn,
    required this.promptTr,
    required this.answers,
  });

  final String id;
  final RelationshipTopic topic;
  final String promptEn;
  final String promptTr;
  final List<RelationshipAnswerOption> answers;

  String promptFor(String languageCode) {
    return languageCode == 'tr' ? promptTr : promptEn;
  }

  bool hasAnswer(String answerId) {
    return answers.any((item) => item.id == answerId);
  }
}

const _bother = [
  RelationshipAnswerOption(
    id: 'a',
    labelEn: 'Yes, that would bother me',
    labelTr: 'Evet, bu beni rahatsız eder',
  ),
  RelationshipAnswerOption(
    id: 'b',
    labelEn: 'No, that would not bother me',
    labelTr: 'Hayır, bu beni rahatsız etmez',
  ),
  RelationshipAnswerOption(
    id: 'c',
    labelEn: 'It depends on the situation',
    labelTr: 'Duruma göre değişir',
  ),
];

const _agree = [
  RelationshipAnswerOption(id: 'a', labelEn: 'I agree', labelTr: 'Katılıyorum'),
  RelationshipAnswerOption(
    id: 'b',
    labelEn: 'I disagree',
    labelTr: 'Katılmıyorum',
  ),
  RelationshipAnswerOption(
    id: 'c',
    labelEn: 'It depends',
    labelTr: 'Duruma göre değişir',
  ),
];

const _acceptable = [
  RelationshipAnswerOption(
    id: 'a',
    labelEn: 'That is acceptable to me',
    labelTr: 'Bu benim için kabul edilebilir',
  ),
  RelationshipAnswerOption(
    id: 'b',
    labelEn: 'That is not acceptable to me',
    labelTr: 'Bu benim için kabul edilebilir değil',
  ),
  RelationshipAnswerOption(
    id: 'c',
    labelEn: 'It depends on the details',
    labelTr: 'Detaylara göre değişir',
  ),
];

const _timing = [
  RelationshipAnswerOption(
    id: 'a',
    labelEn: 'Talk about it right away',
    labelTr: 'Hemen konuşmak',
  ),
  RelationshipAnswerOption(
    id: 'b',
    labelEn: 'Take space first, then talk',
    labelTr: 'Önce alan açıp sonra konuşmak',
  ),
  RelationshipAnswerOption(
    id: 'c',
    labelEn: 'It depends on the moment',
    labelTr: 'Ana göre değişir',
  ),
];

const _priority = [
  RelationshipAnswerOption(
    id: 'a',
    labelEn: 'The relationship should come first',
    labelTr: 'İlişki öncelikli olmalı',
  ),
  RelationshipAnswerOption(
    id: 'b',
    labelEn: 'Individual life should stay equally important',
    labelTr: 'Bireysel hayat eşit derecede önemli kalmalı',
  ),
  RelationshipAnswerOption(
    id: 'c',
    labelEn: 'It depends on the season of life',
    labelTr: 'Hayat dönemine göre değişir',
  ),
];

RelationshipQuestion _q(
  int n,
  RelationshipTopic topic,
  String en,
  String tr, [
  List<RelationshipAnswerOption> answers = _bother,
]) {
  return RelationshipQuestion(
    id: 'rq_${n.toString().padLeft(3, '0')}',
    topic: topic,
    promptEn: en,
    promptTr: tr,
    answers: answers,
  );
}

/// Static catalog. Question text is never written to each user's answers.
abstract final class RelationshipQuestionCatalog {
  static const int version = 1;

  static final List<RelationshipQuestion> questions = [
    _q(
      1,
      RelationshipTopic.friendship,
      'Would it bother you if your partner had a very close friend of another gender?',
      'Sevgilinin karşı cinsten çok yakın bir arkadaşı olması senin için sorun olur mu?',
    ),
    _q(
      2,
      RelationshipTopic.exes,
      'Is it acceptable for a partner to stay friends with an ex?',
      'Sevgilinin eski sevgilisiyle arkadaş kalması senin için kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      3,
      RelationshipTopic.boundaries,
      'Is checking a partner\'s phone a normal part of a relationship?',
      'Bir ilişkide partnerinin telefonunu kontrol etmek normal midir?',
      _agree,
    ),
    _q(
      4,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner went on a trip with friends without you?',
      'Sevgilinin arkadaşlarıyla sensiz tatile gitmesi senin için sorun olur mu?',
    ),
    _q(
      5,
      RelationshipTopic.jealousy,
      'Is jealousy a sign of love in a relationship?',
      'İlişkide kıskançlık sevginin bir göstergesi midir?',
      _agree,
    ),
    _q(
      6,
      RelationshipTopic.friendship,
      'Would it bother you if your partner had a one-on-one dinner with someone of another gender?',
      'Partnerinin karşı cinsten biriyle baş başa yemek yemesi sorun olur mu?',
    ),
    _q(
      7,
      RelationshipTopic.personalSpace,
      'Should everyone in a relationship keep some private space of their own?',
      'Bir ilişkide herkesin kendi özel alanının olması gerektiğini düşünüyor musun?',
      _agree,
    ),
    _q(
      8,
      RelationshipTopic.communication,
      'If your partner hid something from you, is it better to wait than to bring it up directly?',
      'Sevgilin senden bazı şeyleri saklıyorsa bunu doğrudan konuşmak yerine beklemek doğru mudur?',
      _agree,
    ),
    _q(
      9,
      RelationshipTopic.money,
      'Should couples handle money as a completely shared pool?',
      'Bir ilişkide para konusunda tamamen ortak hareket etmek gerekir mi?',
      _agree,
    ),
    _q(
      10,
      RelationshipTopic.exes,
      'Would it bother you if your partner followed an ex on social media?',
      'Partnerinin sosyal medyada eski sevgilisini takip etmesi senin için sorun olur mu?',
    ),
    _q(
      11,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner went out at night with friends without telling you first?',
      'Sevgilinin senden habersiz arkadaşlarıyla gece dışarı çıkması sorun olur mu?',
    ),
    _q(
      12,
      RelationshipTopic.communication,
      'During an argument, is it better to step away and cool down, or talk immediately?',
      'Bir ilişkide tartışma sırasında biraz uzaklaşıp sakinleşmek mi, yoksa hemen konuşmak mı daha doğrudur?',
      _timing,
    ),
    _q(
      13,
      RelationshipTopic.expectations,
      'Can different political or social views become a relationship problem?',
      'Partnerinin senden farklı siyasi veya sosyal görüşlere sahip olması ilişkide sorun yaratır mı?',
    ),
    _q(
      14,
      RelationshipTopic.communication,
      'Should partners tell each other everything?',
      'Bir ilişkide partnerlerin birbirlerine her şeyi anlatması gerektiğini düşünüyor musun?',
      _agree,
    ),
    _q(
      15,
      RelationshipTopic.flirting,
      'If you thought your partner was flirting with someone, would you talk first rather than withdraw?',
      'Sevgilin başka biriyle flört ettiğini düşündüğün bir davranış sergilerse önce konuşmayı mı tercih edersin?',
      _agree,
    ),
    _q(
      16,
      RelationshipTopic.trust,
      'Should a partner share phone or social-media passwords?',
      'Partnerlerin telefon veya sosyal medya şifrelerini paylaşması gerekir mi?',
      _agree,
    ),
    _q(
      17,
      RelationshipTopic.loyalty,
      'Is emotional closeness with someone else as serious as physical closeness?',
      'Başka birine duygusal yakınlık, fiziksel yakınlık kadar ciddi midir?',
      _agree,
    ),
    _q(
      18,
      RelationshipTopic.boundaries,
      'Would it bother you if your partner spent a weekend at a friend\'s house without you?',
      'Partnerinin sensiz bir arkadaşının evinde hafta sonu geçirmesi sorun olur mu?',
    ),
    _q(
      19,
      RelationshipTopic.futurePlans,
      'Should couples agree on whether they want children before getting serious?',
      'Ciddi olmadan önce çocuk isteyip istemedikleri konusunda çiftler anlaşmalı mıdır?',
      _agree,
    ),
    _q(
      20,
      RelationshipTopic.money,
      'Would it bother you if your partner earned much more or much less than you?',
      'Partnerinin senden çok daha fazla veya çok daha az kazanması sorun olur mu?',
    ),
    _q(
      21,
      RelationshipTopic.socialLife,
      'Should a partner always invite you when going out with a mixed group of friends?',
      'Partner, karma bir arkadaş grubuyla dışarı çıkarken seni her zaman davet etmeli midir?',
      _agree,
    ),
    _q(
      22,
      RelationshipTopic.jealousy,
      'Would it bother you if people openly complimented your partner in front of you?',
      'İnsanların yanında partnerine açıkça iltifat etmesi seni rahatsız eder mi?',
    ),
    _q(
      23,
      RelationshipTopic.trust,
      'Is it okay for a partner to keep a few personal diaries or notes private?',
      'Partnerin birkaç kişisel notunu veya günlüğünü özel tutması kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      24,
      RelationshipTopic.exes,
      'Would it bother you if your partner still had photos with an ex in their gallery?',
      'Partnerinin galerisinde eski sevgilisiyle fotoğraflarının olması sorun olur mu?',
    ),
    _q(
      25,
      RelationshipTopic.communication,
      'Should difficult topics be discussed the same day they come up?',
      'Zor konular ortaya çıktığı gün mü konuşulmalıdır?',
      _agree,
    ),
    _q(
      26,
      RelationshipTopic.friendship,
      'Would it bother you if your partner had a regular one-on-one hobby with a close friend of another gender?',
      'Partnerinin karşı cinsten yakın bir arkadaşıyla düzenli baş başa hobisi olması sorun olur mu?',
    ),
    _q(
      27,
      RelationshipTopic.personalSpace,
      'Is it healthy for partners to take separate vacations once in a while?',
      'Partnerlerin ara sıra ayrı tatil yapması sağlıklı mıdır?',
      _agree,
    ),
    _q(
      28,
      RelationshipTopic.loyalty,
      'Would it bother you if your partner stayed in touch with someone who previously liked them romantically?',
      'Daha önce romantik ilgi göstermiş biriyle partnerinin iletişimde kalması sorun olur mu?',
    ),
    _q(
      29,
      RelationshipTopic.money,
      'Should large purchases be discussed together before they are made?',
      'Büyük harcamalar yapılmadan önce birlikte konuşulmalı mıdır?',
      _agree,
    ),
    _q(
      30,
      RelationshipTopic.expectations,
      'Should partners spend most weekends together?',
      'Partnerler hafta sonlarının çoğunu birlikte mi geçirmelidir?',
      _priority,
    ),
    _q(
      31,
      RelationshipTopic.flirting,
      'Is light joking with strangers okay when you are in a relationship?',
      'İlişkideyken yabancılarla hafif şakalaşmak kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      32,
      RelationshipTopic.boundaries,
      'Would it bother you if your partner read your messages without asking?',
      'Partnerinin sormadan mesajlarını okuması sorun olur mu?',
    ),
    _q(
      33,
      RelationshipTopic.trust,
      'If plans change, should a partner update you as soon as they can?',
      'Planlar değişince partner mümkün olan en kısa sürede haber vermeli midir?',
      _agree,
    ),
    _q(
      34,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner\'s friends disliked you?',
      'Partnerinin arkadaşlarının senden hoşlanmaması sorun olur mu?',
    ),
    _q(
      35,
      RelationshipTopic.futurePlans,
      'Should couples live in the same city before calling the relationship long-term?',
      'İlişkiyi uzun vadeli saymadan önce aynı şehirde yaşamak gerekir mi?',
      _agree,
    ),
    _q(
      36,
      RelationshipTopic.jealousy,
      'Would it bother you if your partner liked a lot of photos of people they find attractive?',
      'Partnerinin çekici bulduğu insanların fotoğraflarına sıkça beğeni atması sorun olur mu?',
    ),
    _q(
      37,
      RelationshipTopic.communication,
      'Is silent treatment ever a fair way to handle conflict?',
      'Tartışmada karşılık vermemek adil bir yol olabilir mi?',
      _agree,
    ),
    _q(
      38,
      RelationshipTopic.personalSpace,
      'Should partners be okay with some evenings spent completely apart?',
      'Partnerlerin bazı akşamları tamamen ayrı geçirmesi normal midir?',
      _agree,
    ),
    _q(
      39,
      RelationshipTopic.exes,
      'Would it bother you if your partner worked on a project with an ex?',
      'Partnerinin eski sevgilisiyle bir projede çalışması sorun olur mu?',
    ),
    _q(
      40,
      RelationshipTopic.money,
      'Should each partner keep some money that is only theirs?',
      'Her partnerin yalnızca kendisine ait bir miktar parası olmalı mıdır?',
      _agree,
    ),
    _q(
      41,
      RelationshipTopic.loyalty,
      'Is a close emotional venting friendship with someone else a problem if you are dating?',
      'Flört ederken başka birine duygularını dökmek sorun mudur?',
      _agree,
    ),
    _q(
      42,
      RelationshipTopic.friendship,
      'Would it bother you if your partner hugged friends of another gender as a greeting?',
      'Partnerinin karşı cinsten arkadaşlarını selamlamak için kucaklaması sorun olur mu?',
    ),
    _q(
      43,
      RelationshipTopic.expectations,
      'Should partners share similar energy for going out versus staying in?',
      'Partnerlerin dışarı çıkma ve evde kalma enerjilerinin benzer olması gerekir mi?',
      _agree,
    ),
    _q(
      44,
      RelationshipTopic.communication,
      'If something small bothers you, should you mention it instead of letting it pass?',
      'Küçük bir şey rahatsız ederse geçiştirmek yerine söylemek mi gerekir?',
      _agree,
    ),
    _q(
      45,
      RelationshipTopic.boundaries,
      'Would it bother you if your partner posted couple photos without asking you first?',
      'Partnerinin sormadan çift fotoğrafı paylaşması sorun olur mu?',
    ),
    _q(
      46,
      RelationshipTopic.trust,
      'Is it okay not to share every social plan in advance if you will still come home as usual?',
      'Her sosyal planı önceden paylaşmamak, eve her zamanki gibi döneceksen kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      47,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner had a weekly hangout you were not part of?',
      'Partnerinin senin dahil olmadığın haftalık bir buluşması olması sorun olur mu?',
    ),
    _q(
      48,
      RelationshipTopic.futurePlans,
      'Should marriage be discussed within the first year of a serious relationship?',
      'Ciddi bir ilişkinin ilk yılında evlilik konuşulmalı mıdır?',
      _agree,
    ),
    _q(
      49,
      RelationshipTopic.flirting,
      'Would it bother you if your partner kept an old dating-app account even without using it?',
      'Partnerinin kullanmasa bile eski bir tanışma uygulaması hesabını tutması sorun olur mu?',
    ),
    _q(
      50,
      RelationshipTopic.jealousy,
      'Is asking who someone is texting a reasonable question in a relationship?',
      'Kiminle mesajlaştığını sormak ilişkide makul bir soru mudur?',
      _agree,
    ),
    _q(
      51,
      RelationshipTopic.exes,
      'Would it bother you if your partner said kind things about an ex\'s character?',
      'Partnerinin eski sevgilisinin karakteri hakkında olumlu şeyler söylemesi sorun olur mu?',
    ),
    _q(
      52,
      RelationshipTopic.money,
      'Should couples split shared bills evenly even if incomes differ?',
      'Gelirler farklı olsa bile ortak faturalar eşit mi bölünmelidir?',
      _agree,
    ),
    _q(
      53,
      RelationshipTopic.personalSpace,
      'Is it okay for a partner to have hobbies you have no interest in joining?',
      'Partnerin senin ilgi duymadığın hobileri olması kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      54,
      RelationshipTopic.communication,
      'Should apologies come quickly after a disagreement, even if the issue is not fully solved?',
      'Anlaşmazlıktan sonra konu tam çözülmese bile özür hızlı mı gelmelidir?',
      _agree,
    ),
    _q(
      55,
      RelationshipTopic.friendship,
      'Would it bother you if your partner\'s best friend was someone they once dated?',
      'Partnerinin en yakın arkadaşının eskiden çıktığı biri olması sorun olur mu?',
    ),
    _q(
      56,
      RelationshipTopic.loyalty,
      'Would it bother you if your partner kept a private chat with someone you have never met?',
      'Hiç tanımadığın biriyle partnerinin özel sohbeti olması sorun olur mu?',
    ),
    _q(
      57,
      RelationshipTopic.boundaries,
      'Should a partner be able to say no to a family event without it becoming a fight?',
      'Partner, kavga olmadan bir aile etkinliğine hayır diyebilmeli midir?',
      _agree,
    ),
    _q(
      58,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner got home very late after a work dinner?',
      'Partnerinin iş yemeğinden çok geç gelmesi sorun olur mu?',
    ),
    _q(
      59,
      RelationshipTopic.trust,
      'Is location sharing between partners a comfort or a pressure?',
      'Partnerler arası konum paylaşımı rahatlık mıdır, baskı mıdır?',
      _agree,
    ),
    _q(
      60,
      RelationshipTopic.expectations,
      'Should partners text good morning and good night most days?',
      'Partnerler çoğu gün günaydın ve iyi geceler yazmalı mıdır?',
      _agree,
    ),
    _q(
      61,
      RelationshipTopic.futurePlans,
      'Would it bother you if your partner wanted to live abroad for a year without you at first?',
      'Partnerinin önce sensiz bir yıl yurt dışında yaşamak istemesi sorun olur mu?',
    ),
    _q(
      62,
      RelationshipTopic.flirting,
      'Is accepting a compliment from a stranger okay when you are in a relationship?',
      'İlişkideyken bir yabancının iltifatını kabul etmek sorun mudur?',
      _acceptable,
    ),
    _q(
      63,
      RelationshipTopic.jealousy,
      'Would it bother you if your partner spent more time with friends than with you for a while?',
      'Partnerinin bir süre seninle olduğundan daha çok arkadaşlarıyla vakit geçirmesi sorun olur mu?',
    ),
    _q(
      64,
      RelationshipTopic.communication,
      'Should partners talk about attraction to other people honestly?',
      'Partnerler başka insanlara duyulan çekimi dürüstçe konuşmalı mıdır?',
      _agree,
    ),
    _q(
      65,
      RelationshipTopic.money,
      'Would it bother you if your partner lent a large amount of money to a friend without asking you?',
      'Partnerinin sormadan bir arkadaşına büyük miktarda borç vermesi sorun olur mu?',
    ),
    _q(
      66,
      RelationshipTopic.exes,
      'Is it okay to keep gifts from an ex if they have no romantic meaning anymore?',
      'Romantik anlamı kalmadıysa eski sevgiliden hediyeleri tutmak kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      67,
      RelationshipTopic.personalSpace,
      'Should partners knock or ask before using each other\'s devices?',
      'Partnerler birbirlerinin cihazlarını kullanmadan önce sormalı mıdır?',
      _agree,
    ),
    _q(
      68,
      RelationshipTopic.friendship,
      'Would it bother you if your partner stayed overnight at a friend\'s after a late event?',
      'Geç bir etkinlikten sonra partnerinin arkadaşında kalması sorun olur mu?',
    ),
    _q(
      69,
      RelationshipTopic.loyalty,
      'Is keeping a list of people you find interesting a problem in a relationship?',
      'İlginç bulduğun kişilerin bir listesini tutmak ilişkide sorun mudur?',
      _agree,
    ),
    _q(
      70,
      RelationshipTopic.boundaries,
      'Should a partner be allowed to decline intimacy without explaining every time?',
      'Partner, her seferinde açıklama yapmadan yakınlığı reddedebilmeli midir?',
      _agree,
    ),
    _q(
      71,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner joined a club or team you could not be part of?',
      'Partnerinin senin katılamayacağın bir kulübe veya takıma girmesi sorun olur mu?',
    ),
    _q(
      72,
      RelationshipTopic.trust,
      'If a partner is quiet for a day, should you assume something is wrong?',
      'Partner bir gün sessizse bir şeylerin ters gittiğini varsaymalı mısın?',
      _agree,
    ),
    _q(
      73,
      RelationshipTopic.futurePlans,
      'Should couples agree on how close they want to live to family?',
      'Aileye ne kadar yakın yaşanacağı konusunda çiftler anlaşmalı mıdır?',
      _agree,
    ),
    _q(
      74,
      RelationshipTopic.expectations,
      'Is it important that partners have similar views on religion or spiritual life?',
      'Partnerlerin din veya spiritüel hayat konusunda benzer görüşleri önemli midir?',
      _agree,
    ),
    _q(
      75,
      RelationshipTopic.flirting,
      'Would it bother you if your partner danced closely with someone else at a party?',
      'Partnerinin bir partide başka biriyle yakın dans etmesi sorun olur mu?',
    ),
    _q(
      76,
      RelationshipTopic.communication,
      'Should a partner tell you when they are upset with a friend, even if it is not about you?',
      'Partner, seninle ilgili olmasa bile bir arkadaşına kırıldığını söylemeli midir?',
      _agree,
    ),
    _q(
      77,
      RelationshipTopic.money,
      'Would it bother you if your partner was secretive about their personal spending?',
      'Partnerinin kişisel harcamaları konusunda ketum olması sorun olur mu?',
    ),
    _q(
      78,
      RelationshipTopic.jealousy,
      'Is looking through a partner\'s social likes a reasonable check-in?',
      'Partnerin sosyal medya beğenilerine bakmak makul bir kontrol müdür?',
      _agree,
    ),
    _q(
      79,
      RelationshipTopic.exes,
      'Would it bother you if your partner still celebrated an ex\'s birthday with a message?',
      'Partnerinin eski sevgilisine doğum gününde mesaj atması sorun olur mu?',
    ),
    _q(
      80,
      RelationshipTopic.personalSpace,
      'Should partners be comfortable with some friendships you never join?',
      'Hiç katılmadığın bazı arkadaşlıklara partnerinin sahip olması rahat mı karşılanmalıdır?',
      _agree,
    ),
    _q(
      81,
      RelationshipTopic.loyalty,
      'Would it bother you if your partner deleted chats before you could see them?',
      'Partnerinin sen görmeden sohbetleri silmesi sorun olur mu?',
    ),
    _q(
      82,
      RelationshipTopic.friendship,
      'Is it okay for a partner to have a standing coffee date with a coworker of another gender?',
      'Partnerinin karşı cinsten bir iş arkadaşıyla düzenli kahve buluşması kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      83,
      RelationshipTopic.boundaries,
      'Should family members be allowed to comment freely on your relationship?',
      'Aile üyelerinin ilişkiniz hakkında serbestçe yorum yapması kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      84,
      RelationshipTopic.socialLife,
      'Would it bother you if your partner skipped a plan with you to help a friend in a mild crisis?',
      'Hafif bir kriz için partnerinin seninle planı iptal edip arkadaşına yardım etmesi sorun olur mu?',
    ),
    _q(
      85,
      RelationshipTopic.communication,
      'Is it better to write a long message than to argue in person when emotions are high?',
      'Duygular yüksekken yüz yüze tartışmak yerine uzun bir mesaj yazmak daha mı iyidir?',
      _agree,
    ),
    _q(
      86,
      RelationshipTopic.trust,
      'Should a partner tell you if they were attracted to someone they met that day?',
      'O gün tanıştığı birine ilgi duysa partner bunu söylemeli midir?',
      _agree,
    ),
    _q(
      87,
      RelationshipTopic.futurePlans,
      'Would it bother you if your partner was unsure about long-term commitment after a year together?',
      'Bir yıl sonra partnerinin uzun vadeli bağlılık konusunda emin olmaması sorun olur mu?',
    ),
    _q(
      88,
      RelationshipTopic.money,
      'Should couples keep a shared budget even while dating, not only after moving in?',
      'Birlikte yaşamadan önce de ortak bütçe tutulmalı mıdır?',
      _agree,
    ),
    _q(
      89,
      RelationshipTopic.expectations,
      'Is matching love languages necessary for a relationship to work?',
      'İlişkinin yürümesi için sevgi dillerinin uyuşması gerekli midir?',
      _agree,
    ),
    _q(
      90,
      RelationshipTopic.flirting,
      'Would it bother you if your partner used playful nicknames with someone else?',
      'Partnerinin başka birine şakacı lakaplar takması sorun olur mu?',
    ),
    _q(
      91,
      RelationshipTopic.jealousy,
      'Should a partner avoid wearing outfits you feel uncomfortable with in public?',
      'Partner, senin rahatsız olduğun kıyafetleri dışarıda giymekten kaçınmalı mıdır?',
      _agree,
    ),
    _q(
      92,
      RelationshipTopic.exes,
      'Is it okay to stay in a group chat that still includes an ex?',
      'Eski sevgilinin de olduğu bir grup sohbetinde kalmak kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      93,
      RelationshipTopic.personalSpace,
      'Would it bother you if your partner needed a full day alone each week?',
      'Partnerinin her hafta tam bir gün yalnız kalmak istemesi sorun olur mu?',
    ),
    _q(
      94,
      RelationshipTopic.loyalty,
      'Is keeping an old love letter in a drawer a problem?',
      'Eski bir aşk mektubunu çekmecede tutmak sorun mudur?',
      _agree,
    ),
    _q(
      95,
      RelationshipTopic.friendship,
      'Would it bother you if your partner shared personal relationship worries with a friend before you?',
      'Partnerinin ilişki kaygılarını senden önce bir arkadaşla paylaşması sorun olur mu?',
    ),
    _q(
      96,
      RelationshipTopic.boundaries,
      'Should partners ask before posting about arguments, even as a joke?',
      'Tartışmaları şaka bile olsa paylaşmadan önce sormalı mıdır?',
      _agree,
    ),
    _q(
      97,
      RelationshipTopic.socialLife,
      'Is it okay for a partner to go to a concert without you if you dislike the artist?',
      'Sanatçıyı sen sevmiyorsan partnerin sensiz konsere gitmesi kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      98,
      RelationshipTopic.communication,
      'Should a partner say "I need time" instead of disappearing during conflict?',
      'Çatışmada kaybolmak yerine "zamana ihtiyacım var" demek gerekir mi?',
      _agree,
    ),
    _q(
      99,
      RelationshipTopic.trust,
      'Would it bother you if your partner hid a failing grade, job issue, or family stress to "protect" you?',
      'Partnerinin seni korumak için not, iş veya aile stresini gizlemesi sorun olur mu?',
    ),
    _q(
      100,
      RelationshipTopic.futurePlans,
      'Should pets, children, or caregiving plans be aligned before moving in together?',
      'Birlikte taşınmadan önce evcil hayvan, çocuk veya bakım planları uyuşmalı mıdır?',
      _agree,
    ),
    _q(
      101,
      RelationshipTopic.money,
      'Would it bother you if your partner frequently paid for friends while being careful with you?',
      'Partnerinin seninle dikkatli harcayıp arkadaşlarına sık sık ısmarlaması sorun olur mu?',
    ),
    _q(
      102,
      RelationshipTopic.expectations,
      'Is it important that partners want a similar level of public affection?',
      'Partnerlerin benzer düzeyde herkese açık sevgi göstermesi önemli midir?',
      _agree,
    ),
    _q(
      103,
      RelationshipTopic.flirting,
      'Would it bother you if your partner kept chatting with someone who clearly likes them?',
      'Açıkça ilgi duyan biriyle partnerinin sohbeti sürdürmesi sorun olur mu?',
    ),
    _q(
      104,
      RelationshipTopic.jealousy,
      'Should a partner introduce you quickly to new friends they spend time with?',
      'Partner, vakit geçirdiği yeni arkadaşlarına seni çabuk tanıtmalı mıdır?',
      _agree,
    ),
    _q(
      105,
      RelationshipTopic.exes,
      'Would it bother you if your partner still used a playlist an ex made?',
      'Partnerinin eski sevgilisinin yaptığı çalma listesini kullanması sorun olur mu?',
    ),
    _q(
      106,
      RelationshipTopic.personalSpace,
      'Is it okay not to share every password if honesty is otherwise strong?',
      'Dürüstlük güçlüyse her şifreyi paylaşmamak kabul edilebilir mi?',
      _acceptable,
    ),
    _q(
      107,
      RelationshipTopic.loyalty,
      'Would it bother you if your partner said "I love you" later than you did?',
      'Partnerinin "seni seviyorum"u senden sonra söylemesi sorun olur mu?',
    ),
    _q(
      108,
      RelationshipTopic.communication,
      'Should check-ins about the relationship happen on a regular schedule?',
      'İlişki hakkında düzenli kontrol konuşmaları yapılmalı mıdır?',
      _agree,
    ),
    _q(
      109,
      RelationshipTopic.friendship,
      'Would it bother you if your partner\'s friend group knew private details you had not agreed to share?',
      'Partnerinin arkadaş grubunun senin paylaşmayı kabul etmediğin özel detayları bilmesi sorun olur mu?',
    ),
    _q(
      110,
      RelationshipTopic.boundaries,
      'Should a partner support your no even when their family disagrees?',
      'Kendi ailesi katılmasa bile partnerin senin hayır dediğin şeyi desteklemeli midir?',
      _agree,
    ),
  ];

  static RelationshipQuestion? byId(String id) {
    for (final question in questions) {
      if (question.id == id) {
        return question;
      }
    }
    return null;
  }

  static List<RelationshipQuestion> unanswered(Set<String> answeredIds) {
    return questions.where((item) => !answeredIds.contains(item.id)).toList();
  }

  static bool isValidAnswer({
    required String questionId,
    required String answerId,
  }) {
    final question = byId(questionId);
    return question != null && question.hasAnswer(answerId);
  }
}
