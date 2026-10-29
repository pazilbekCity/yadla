/// Supported interface languages stored in `app_settings` under
/// `interface_language` (`kaa`, `uz`, `ru`).
enum AppLanguage {
  kaa('kaa', 'Qaraqalpaqsha'),
  uz('uz', 'Oʻzbekcha'),
  ru('ru', 'Русский');

  const AppLanguage(this.code, this.nativeName);

  final String code;
  final String nativeName;

  /// Resolves a stored language code to an [AppLanguage], defaulting to
  /// Karakalpak ([AppLanguage.kaa]) when null or unrecognized.
  static AppLanguage fromCode(String? code) {
    for (final lang in AppLanguage.values) {
      if (lang.code == code) return lang;
    }
    return AppLanguage.kaa;
  }
}

/// Centralized user-facing UI strings localized in Karakalpak (`kaa`),
/// Uzbek (`uz`), and Russian (`ru`).
class S {
  const S._();

  static AppLanguage _current = AppLanguage.kaa;

  /// Currently active UI language (defaults to [AppLanguage.kaa]).
  static AppLanguage get currentLanguage => _current;

  /// Updates the active UI language in memory.
  static void setLanguage(AppLanguage language) {
    _current = language;
  }

  /// Updates the active UI language from a stored code (`kaa`, `uz`, `ru`).
  static void setLanguageCode(String? code) {
    _current = AppLanguage.fromCode(code);
  }

  static T _pick<T>({
    required T kaa,
    required T uz,
    required T ru,
  }) {
    switch (_current) {
      case AppLanguage.kaa:
        return kaa;
      case AppLanguage.uz:
        return uz;
      case AppLanguage.ru:
        return ru;
    }
  }

  // General
  static const appTitle = 'Anki APK';

  static String get selectLanguage => _pick(
        kaa: 'Tildi tańlaw',
        uz: 'Tilni tanlash',
        ru: 'Выбрать язык',
      );

  static String get add => _pick(
        kaa: 'Qosıw',
        uz: 'Qoʻshish',
        ru: 'Добавить',
      );

  static String get edit => _pick(
        kaa: 'Ózgertiw',
        uz: 'Tahrirlash',
        ru: 'Изменить',
      );

  static String get delete => _pick(
        kaa: 'Óshiriw',
        uz: 'Oʻchirish',
        ru: 'Удалить',
      );

  static String get cancel => _pick(
        kaa: 'Biykarlaw',
        uz: 'Bekor qilish',
        ru: 'Отмена',
      );

  static String get save => _pick(
        kaa: 'Saqlaw',
        uz: 'Saqlash',
        ru: 'Сохранить',
      );

  static String get retry => _pick(
        kaa: 'Qayta urınıw',
        uz: 'Qayta urinish',
        ru: 'Повторить',
      );

  static String get loading => _pick(
        kaa: 'Júklenbekte...',
        uz: 'Yuklanmoqda...',
        ru: 'Загрузка...',
      );

  static String get name => _pick(
        kaa: 'Atı',
        uz: 'Nomi',
        ru: 'Название',
      );

  static String get description => _pick(
        kaa: 'Sıpatlama (ixtiyariy)',
        uz: 'Tavsif (ixtiyoriy)',
        ru: 'Описание (необязательно)',
      );

  static String get nameRequired => _pick(
        kaa: 'Atın kiritiń.',
        uz: 'Nomini kiriting.',
        ru: 'Введите название.',
      );

  static String get deleteIrreversible => _pick(
        kaa: 'Bul ámeldi qaytarıp bolmaydı.',
        uz: 'Bu amalni ortga qaytarib boʻlmaydi.',
        ru: 'Это действие нельзя отменить.',
      );

  static String loadError(Object e) => _pick(
        kaa: 'Maǵlıwmatlardı júklewde qátelik: $e',
        uz: 'Maʼlumotlarni yuklashda xatolik: $e',
        ru: 'Ошибка загрузки данных: $e',
      );

  static String confirmDelete(String name) => _pick(
        kaa: '«$name» óshirilsin be?',
        uz: '«$name» oʻchirilsinmi?',
        ru: 'Удалить «$name»?',
      );

  static String deleteBlocked(String name) => _pick(
        kaa: '«$name» óshirilmedi: onıń ishinde basqa maǵlıwmatlar bar. '
            'Aldın ishindegi elementlerdi óshiriń.',
        uz: '«$name» oʻchirilmadi: uning ichida boshqa maʼlumotlar bor. '
            'Avval ichidagi elementlarni oʻchiring.',
        ru: '«$name» не удалено: внутри есть вложенные данные. '
            'Сначала удалите вложенные элементы.',
      );

  // Database errors
  static String get errNotFound => _pick(
        kaa: 'Jazıw tabılmadı (ol basqa jerde óshirilgen bolıwı múmkin).',
        uz: 'Yozuv topilmadi (u boshqa joyda oʻchirilgan boʻlishi mumkin).',
        ru: 'Запись не найдена (возможно, она уже была удалена).',
      );

  static String get errValidation => _pick(
        kaa: 'Kiritilgen mánis durıs emes.',
        uz: 'Kiritilgan qiymat notoʻgʻri.',
        ru: 'Введено некорректное значение.',
      );

  static String get errDuplicate => _pick(
        kaa: 'Bunday atlı element bar. Basqa at kiritiń.',
        uz: 'Bunday nomli element mavjud. Boshqa nom kiriting.',
        ru: 'Элемент с таким названием уже существует. Введите другое название.',
      );

  static String get errInvalidReference => _pick(
        kaa: 'Ata-ana jazıw tabılmadı.',
        uz: 'Yuqori turuvchi yozuv topilmadi.',
        ru: 'Родительская запись не найдена.',
      );

  static String get errHasDependents => _pick(
        kaa: 'Óshiriw múmkin emes: ishinde basqa maǵlıwmatlar bar.',
        uz: 'Oʻchirish mumkin emas: ichida boshqa maʼlumotlar bor.',
        ru: 'Невозможно удалить: внутри есть зависимые данные.',
      );

  static String get errDowngrade => _pick(
        kaa: 'Maǵlıwmatlar bazası jańaraq versiyadan. Qosımshanı jańalań.',
        uz: 'Maʼlumotlar bazasi yangiroq versiyaga tegishli. Ilovani yangilang.',
        ru: 'База данных создана в более новой версии. Обновите приложение.',
      );

  static String get errCorrupted => _pick(
        kaa: 'Maǵlıwmatlar bazası zaqımlanǵan.',
        uz: 'Maʼlumotlar bazasi shikastlangan.',
        ru: 'База данных повреждена.',
      );

  static String get errUnknown => _pick(
        kaa: 'Maǵlıwmatlar bazasında qátelik júz berdi.',
        uz: 'Maʼlumotlar bazasida xatolik yuz berdi.',
        ru: 'Произошла ошибка базы данных.',
      );

  // Subjects
  static String get subjectsEmpty => _pick(
        kaa: 'Áli pánler joq. «Pán qosıw» túymesin basıń.',
        uz: 'Hali fanlar yoʻq. «Fan qoʻshish» tugmasini bosing.',
        ru: 'Предметов пока нет. Нажмите «Добавить предмет».',
      );

  static String get addSubject => _pick(
        kaa: 'Pán qosıw',
        uz: 'Fan qoʻshish',
        ru: 'Добавить предмет',
      );

  static String get editSubject => _pick(
        kaa: 'Pándi ózgertiw',
        uz: 'Fanni tahrirlash',
        ru: 'Изменить предмет',
      );

  // Books
  static String get booksEmpty => _pick(
        kaa: 'Bul pánde áli kitaplar joq. «Kitap qosıw» túymesin basıń.',
        uz: 'Bu fanda hali kitoblar yoʻq. «Kitob qoʻshish» tugmasini bosing.',
        ru: 'В этом предмете пока нет книг. Нажмите «Добавить книгу».',
      );

  static String get addBook => _pick(
        kaa: 'Kitap qosıw',
        uz: 'Kitob qoʻshish',
        ru: 'Добавить книгу',
      );

  static String get editBook => _pick(
        kaa: 'Kitaptı ózgertiw',
        uz: 'Kitobni tahrirlash',
        ru: 'Изменить книгу',
      );

  // Topics
  static String get topicsEmpty => _pick(
        kaa: 'Bul kitapta áli temalar joq. «Tema qosıw» túymesin basıń.',
        uz: 'Bu kitobda hali mavzular yoʻq. «Mavzu qoʻshish» tugmasini bosing.',
        ru: 'В этой книге пока нет тем. Нажмите «Добавить тему».',
      );

  static String get addTopic => _pick(
        kaa: 'Tema qosıw',
        uz: 'Mavzu qoʻshish',
        ru: 'Добавить тему',
      );

  static String get editTopic => _pick(
        kaa: 'Temanı ózgertiw',
        uz: 'Mavzuni tahrirlash',
        ru: 'Изменить тему',
      );

  // Decks
  static String get decksEmpty => _pick(
        kaa: 'Bul temada áli toplamlar joq. «Toplam qosıw» túymesin basıń.',
        uz: 'Bu mavzuda hali toʻplamlar yoʻq. «Toʻplam qoʻshish» tugmasini bosing.',
        ru: 'В этой теме пока нет колод. Нажмите «Добавить колоду».',
      );

  static String get addDeck => _pick(
        kaa: 'Toplam qosıw',
        uz: 'Toʻplam qoʻshish',
        ru: 'Добавить колоду',
      );

  static String get editDeck => _pick(
        kaa: 'Toplamdı ózgertiw',
        uz: 'Toʻplamni tahrirlash',
        ru: 'Изменить колоду',
      );

  // Flashcards
  static String get flashcardsEmpty => _pick(
        kaa: 'Bul toplamda áli kartochkalar joq. «Kartochka qosıw» túymesin basıń.',
        uz: 'Bu toʻplamda hali kartochkalar yoʻq. «Kartochka qoʻshish» tugmasini bosing.',
        ru: 'В этой колоде пока нет карточек. Нажмите «Добавить карточку».',
      );

  static String get addFlashcard => _pick(
        kaa: 'Kartochka qosıw',
        uz: 'Kartochka qoʻshish',
        ru: 'Добавить карточку',
      );

  static String get editFlashcard => _pick(
        kaa: 'Kartochkanı ózgertiw',
        uz: 'Kartochkani tahrirlash',
        ru: 'Изменить карточку',
      );

  static String cardCount(int n) => _pick(
        kaa: 'Kartochkalar sanı: $n',
        uz: 'Kartochkalar soni: $n',
        ru: 'Количество карточек: $n',
      );

  static String get preview => _pick(
        kaa: 'Kóriw',
        uz: 'Koʻrish',
        ru: 'Просмотр',
      );

  // Flashcard editor
  static String get fieldTarget => _pick(
        kaa: 'Maqset sóz yamasa túsinik',
        uz: 'Maqsadli soʻz yoki tushuncha',
        ru: 'Целевое слово или понятие',
      );

  static String get fieldAssociation => _pick(
        kaa: 'Assotsiaciya yamasa eslep qalıw teksti',
        uz: 'Assotsiatsiya yoki eslab qolish matni',
        ru: 'Ассоциация или мнемоника',
      );

  static String get fieldDefinition => _pick(
        kaa: 'Anıqlama yamasa túsindirme',
        uz: 'Taʼrif yoki izoh',
        ru: 'Определение или объяснение',
      );

  static String get fieldImage => _pick(
        kaa: 'Súwret siltemesi (ixtiyariy)',
        uz: 'Rasm havolasi (ixtiyoriy)',
        ru: 'Путь к изображению (необязательно)',
      );

  static String get fieldPlacement => _pick(
        kaa: 'Súwret ornı',
        uz: 'Rasm joylashuvi',
        ru: 'Расположение изображения',
      );

  static String get placementFront => _pick(
        kaa: 'Aldı',
        uz: 'Oldi',
        ru: 'Спереди',
      );

  static String get placementBack => _pick(
        kaa: 'Artı',
        uz: 'Orqasi',
        ru: 'Сзади',
      );

  static String get placementBoth => _pick(
        kaa: 'Eki tárepte',
        uz: 'Ikki tomonda',
        ru: 'С обеих сторон',
      );

  static String get targetRequired => _pick(
        kaa: 'Maqset sóz yamasa túsinikti kiritiń.',
        uz: 'Maqsadli soʻz yoki tushunchani kiriting.',
        ru: 'Введите целевое слово или понятие.',
      );

  // Preview
  static String get previewTitle => _pick(
        kaa: 'Kartochkanı kóriw',
        uz: 'Kartochkani koʻrish',
        ru: 'Просмотр карточки',
      );

  static String get showDefinition => _pick(
        kaa: 'Anıqlamanı kórsetiw',
        uz: 'Taʼrifni koʻrsatish',
        ru: 'Показать определение',
      );

  static String get hideDefinition => _pick(
        kaa: 'Anıqlamanı jasırıw',
        uz: 'Taʼrifni yashirish',
        ru: 'Скрыть определение',
      );

  static String get noDefinition => _pick(
        kaa: 'Anıqlama kiritilmegen.',
        uz: 'Taʼrif kiritilmagan.',
        ru: 'Определение не указано.',
      );

  static String get imagePlaceholder => _pick(
        kaa: 'Súwret (waqtınsha belgi)',
        uz: 'Rasm (vaqtinchalik belgi)',
        ru: 'Изображение (заглушка)',
      );

  // Study session
  static String get study => _pick(
        kaa: 'Úyreniw',
        uz: 'Oʻrganish',
        ru: 'Учить',
      );

  static String get studyDeck => _pick(
        kaa: 'Toplamdı úyreniw',
        uz: 'Toʻplamni oʻrganish',
        ru: 'Учить колоду',
      );

  static String get studySubject => _pick(
        kaa: 'Pándi úyreniw',
        uz: 'Fanni oʻrganish',
        ru: 'Учить предмет',
      );

  static String get studyEmpty => _pick(
        kaa: 'Úyreniw ushın kartochkalar joq.',
        uz: 'Oʻrganish uchun kartochkalar yoʻq.',
        ru: 'Нет карточек для изучения.',
      );

  static String get previousCard => _pick(
        kaa: 'Aldıńǵı',
        uz: 'Oldingi',
        ru: 'Предыдущая',
      );

  static String get nextCard => _pick(
        kaa: 'Keyingi',
        uz: 'Keyingi',
        ru: 'Следующая',
      );

  static String get finishSession => _pick(
        kaa: 'Juwmaqlaw',
        uz: 'Yakunlash',
        ru: 'Завершить',
      );

  static String get restartSession => _pick(
        kaa: 'Qayta baslaw',
        uz: 'Qayta boshlash',
        ru: 'Начать заново',
      );

  static String get sessionCompleteTitle => _pick(
        kaa: 'Sessiya juwmaqlandı!',
        uz: 'Sessiya yakunlandi!',
        ru: 'Сессия завершена!',
      );

  static String sessionProgress(int completed, int total, int remaining) =>
      _pick(
        kaa: 'Ózlestirildi: $completed / $total • Qaldı: $remaining',
        uz: 'Oʻzlashtirildi: $completed / $total • Qoldi: $remaining',
        ru: 'Изучено: $completed / $total • Осталось: $remaining',
      );

  static String stepIndicator(int current, int totalSteps) => _pick(
        kaa: 'Qádem: $current / $totalSteps',
        uz: 'Qadam: $current / $totalSteps',
        ru: 'Шаг: $current / $totalSteps',
      );

  static String sessionSummary(int uniqueCards, int totalReviews) => _pick(
        kaa: 'Barlıq kartochkalar: $uniqueCards\nJámi juwaplar: $totalReviews',
        uz: 'Jami kartochkalar: $uniqueCards\nJami javoblar: $totalReviews',
        ru: 'Всего карточек: $uniqueCards\nВсего ответов: $totalReviews',
      );

  static String alreadyRated(String ratingLabel) => _pick(
        kaa: 'Bul qádemde bahalandı: $ratingLabel',
        uz: 'Bu qadamda baholandi: $ratingLabel',
        ru: 'Оценено на этом шаге: $ratingLabel',
      );

  // Anki-style 4 rating buttons & initial UI interval labels
  static String get rateAgain => _pick(
        kaa: 'Qayta',
        uz: 'Qayta',
        ru: 'Снова',
      );

  static String get rateHard => _pick(
        kaa: 'Qıyın',
        uz: 'Qiyin',
        ru: 'Трудно',
      );

  static String get rateGood => _pick(
        kaa: 'Jaqsı',
        uz: 'Yaxshi',
        ru: 'Хорошо',
      );

  static String get rateEasy => _pick(
        kaa: 'Ańsat',
        uz: 'Oson',
        ru: 'Легко',
      );

  static String get intervalAgain => _pick(
        kaa: '<1 min.',
        uz: '<1 daq.',
        ru: '<1 мин.',
      );

  static String get intervalHard => _pick(
        kaa: '<6 min.',
        uz: '<6 daq.',
        ru: '<6 мин.',
      );

  static String get intervalGood => _pick(
        kaa: '<10 min.',
        uz: '<10 daq.',
        ru: '<10 мин.',
      );

  static String get intervalEasy => _pick(
        kaa: '5 kún',
        uz: '5 kun',
        ru: '5 дн.',
      );

  // Mastery, suspension, and calculated scheduling
  static String get markMastered => _pick(
        kaa: 'Yad boldı',
        uz: 'Yod boʻldi',
        ru: 'Выучено',
      );

  static String get statusLearning => _pick(
        kaa: 'Úyrenilmekte',
        uz: 'Oʻrganilmoqda',
        ru: 'Изучается',
      );

  static String get statusMastered => _pick(
        kaa: 'Yad boldı',
        uz: 'Yod boʻldi',
        ru: 'Выучено',
      );

  static String get statusSuspended => _pick(
        kaa: 'Toqtatılǵan',
        uz: 'Toʻxtatilgan',
        ru: 'Приостановлено',
      );

  static String get restoreToLearning => _pick(
        kaa: 'Úyreniwge qaytarıw',
        uz: 'Oʻrganishga qaytarish',
        ru: 'Вернуть к изучению',
      );

  static String get suspendCard => _pick(
        kaa: 'Waqtınsha toqtatıw',
        uz: 'Vaqtincha toʻxtatish',
        ru: 'Приостановить',
      );

  static String get cardMarkedMastered => _pick(
        kaa: 'Kartochka «Yad boldı» dep belgilendi.',
        uz: 'Kartochka «Yod boʻldi» deb belgilandi.',
        ru: 'Карточка отмечена как «Выучено».',
      );

  static String get cardAutoMastered => _pick(
        kaa: '4 sessiya izbe-iz «Ańsat»! Kartochka «Yad boldı» dep belgilendi.',
        uz: '4 sessiya ketma-ket «Oson»! Kartochka «Yod boʻldi» deb belgilandi.',
        ru: '4 сессии подряд «Легко»! Карточка отмечена как «Выучено».',
      );

  static String get cardRestoredToLearning => _pick(
        kaa: 'Kartochka úyreniwge qaytarıldı.',
        uz: 'Kartochka oʻrganishga qaytarildi.',
        ru: 'Карточка возвращена к изучению.',
      );

  static String get cardSuspended => _pick(
        kaa: 'Kartochka waqtınsha toqtatıldı.',
        uz: 'Kartochka vaqtincha toʻxtatildi.',
        ru: 'Карточка временно приостановлена.',
      );

  static String calculatedNextReview(int intervalDays) => intervalDays <= 0
      ? _pick(
          kaa: 'Esaplanǵan keyingi qaytalaw: <1 min.',
          uz: 'Hisoblangan keyingi takrorlash: <1 daq.',
          ru: 'Расчётное следующее повторение: <1 мин.',
        )
      : _pick(
          kaa: 'Esaplanǵan keyingi qaytalaw: $intervalDays kún',
          uz: 'Hisoblangan keyingi takrorlash: $intervalDays kun',
          ru: 'Расчётное следующее повторение: $intervalDays дн.',
        );

  // Excel (.xlsx) import
  static String get importExcel => _pick(
        kaa: 'Excel (.xlsx) import',
        uz: 'Excel (.xlsx) import',
        ru: 'Импорт из Excel (.xlsx)',
      );

  static String get importPreviewTitle => _pick(
        kaa: 'Excel importın aldınnan kóriw',
        uz: 'Excel importini oldindan koʻrish',
        ru: 'Предпросмотр импорта Excel',
      );

  static String get confirmImport => _pick(
        kaa: 'Import qılıw',
        uz: 'Import qilish',
        ru: 'Импортировать',
      );

  static String get close => _pick(
        kaa: 'Jabıw',
        uz: 'Yopish',
        ru: 'Закрыть',
      );

  static String importFileName(String name) => _pick(
        kaa: 'Fayl: $name',
        uz: 'Fayl: $name',
        ru: 'Файл: $name',
      );

  static String importValidRows(int n) => _pick(
        kaa: 'Jaramlı qatarlar: $n',
        uz: 'Yaroqli qatorlar: $n',
        ru: 'Корректных строк: $n',
      );

  static String importInvalidRows(int n) => _pick(
        kaa: 'Jaramsız qatarlar: $n',
        uz: 'Yaroqsiz qatorlar: $n',
        ru: 'Некорректных строк: $n',
      );

  static String importDuplicateRows(int n) => _pick(
        kaa: 'Ótkizip jiberiletuǵın dublikatlar: $n',
        uz: 'Oʻtkazib yuboriladigan dublikatlar: $n',
        ru: 'Пропущено дубликатов: $n',
      );

  static String importInvalidRowItem(int rowNumber, String reason) => _pick(
        kaa: '$rowNumber-qatar: $reason',
        uz: '$rowNumber-qator: $reason',
        ru: 'Строка $rowNumber: $reason',
      );

  static String get reasonMissingTarget => _pick(
        kaa: '«target_text» (maqset sóz) bos.',
        uz: '«target_text» (maqsadli soʻz) boʻsh.',
        ru: 'Поле «target_text» (целевое слово) пустое.',
      );

  static String get reasonMissingDefinition => _pick(
        kaa: '«definition_text» (anıqlama) bos.',
        uz: '«definition_text» (taʼrif) boʻsh.',
        ru: 'Поле «definition_text» (определение) пустое.',
      );

  static String get errExcelExtension => _pick(
        kaa: 'Jaramsız fayl túri. Tek «.xlsx» formatındaǵı Excel faylın tańlań.',
        uz: 'Yaroqsiz fayl turi. Faqat «.xlsx» formatidagi Excel faylini tanlang.',
        ru: 'Неверный тип файла. Выберите файл Excel в формате «.xlsx».',
      );

  static String get errExcelCorrupted => _pick(
        kaa: 'Fayldı oqıp bolmadı. Fayl zaqımlanǵan yamasa durıs «.xlsx» formatında emes.',
        uz: 'Faylni oʻqib boʻlmadi. Fayl shikastlangan yoki toʻgʻri «.xlsx» formatida emas.',
        ru: 'Не удалось прочитать файл. Файл повреждён или не является корректным «.xlsx».',
      );

  static String get errExcelEmpty => _pick(
        kaa: 'Excel faylı bos yamasa onda import qılatuǵın qatarlar joq.',
        uz: 'Excel fayli boʻsh yoki unda import qilinadigan qatorlar yoʻq.',
        ru: 'Файл Excel пуст или не содержит строк для импорта.',
      );

  static String errExcelMissingColumns(List<String> cols) => _pick(
        kaa: 'Májbúriy baǵanalar tabılmadı: ${cols.join(', ')}. '
            '1-qatarda «target_text» hám «definition_text» bolıwı shárt.',
        uz: 'Majburiy ustunlar topilmadi: ${cols.join(', ')}. '
            '1-qatorda «target_text» va «definition_text» boʻlishi shart.',
        ru: 'Не найдены обязательные столбцы: ${cols.join(', ')}. '
            'В 1-й строке должны быть «target_text» и «definition_text».',
      );

  static String importSuccessSummary(int imported, int skipped) => _pick(
        kaa: 'Import juwmaqlandı: $imported kartochka qosıldı, '
            '$skipped qatar ótkizip jiberildi.',
        uz: 'Import yakunlandi: $imported ta kartochka qoʻshildi, '
            '$skipped ta qator oʻtkazib yuborildi.',
        ru: 'Импорт завершён: добавлено карточек — $imported, '
            'пропущено строк — $skipped.',
      );

  // Local image selection & display
  static String get pickImage => _pick(
        kaa: 'Súwret tańlaw',
        uz: 'Rasm tanlash',
        ru: 'Выбрать изображение',
      );

  static String get changeImage => _pick(
        kaa: 'Súwretti almastırıw',
        uz: 'Rasmni almashtirish',
        ru: 'Заменить изображение',
      );

  static String get removeImage => _pick(
        kaa: 'Súwretti alıp taslaw',
        uz: 'Rasmni olib tashlash',
        ru: 'Удалить изображение',
      );

  static String get imageMissingOrUnreadable => _pick(
        kaa: 'Súwret faylı tabılmadı yamasa oqıp bolmadı.',
        uz: 'Rasm fayli topilmadi yoki oʻqib boʻlmadi.',
        ru: 'Файл изображения не найден или не читается.',
      );

  static String get errImageExtension => _pick(
        kaa: 'Qollap-quwatlanbaytuǵın súwret formatı (tek PNG, JPG, WEBP, GIF, BMP).',
        uz: 'Qoʻllab-quvvatlanmaydigan rasm formati (faqat PNG, JPG, WEBP, GIF, BMP).',
        ru: 'Неподдерживаемый формат изображения (только PNG, JPG, WEBP, GIF, BMP).',
      );

  static String get errImageEmpty => _pick(
        kaa: 'Tańlanǵan súwret faylı bos yamasa oqılmaydı.',
        uz: 'Tanlangan rasm fayli boʻsh yoki oʻqilmaydi.',
        ru: 'Выбранный файл изображения пуст или не читается.',
      );

  static String get errImageSaveFailed => _pick(
        kaa: 'Súwretti qurılma yadına saqlawda qátelik júz berdi.',
        uz: 'Rasmni qurilma xotirasiga saqlashda xatolik yuz berdi.',
        ru: 'Не удалось сохранить изображение в память устройства.',
      );

  // Offline JSON Backup & Restore
  static String get backupMenuTooltip => _pick(
        kaa: 'Rezerv nusqa hám tiklew',
        uz: 'Zaxira nusxa va tiklash',
        ru: 'Резервная копия и восстановление',
      );

  static String get exportBackup => _pick(
        kaa: 'Rezerv nusqa saqlaw (eksport)',
        uz: 'Zaxira nusxa saqlash (eksport)',
        ru: 'Создать резервную копию (экспорт)',
      );

  static String get importBackup => _pick(
        kaa: 'Rezerv nusqadan tiklew (import)',
        uz: 'Zaxira nusxadan tiklash (import)',
        ru: 'Восстановить из копии (импорт)',
      );

  static String backupExportSuccess(String path, int cards, int images) =>
      _pick(
        kaa: 'Rezerv nusqa saqlandı: $cards kartochka, $images súwret ($path)',
        uz: 'Zaxira nusxa saqlandi: $cards ta kartochka, $images ta rasm ($path)',
        ru: 'Резервная копия сохранена: карточек — $cards, изображений — $images ($path)',
      );

  static String get restorePreviewTitle => _pick(
        kaa: 'Rezerv nusqadan tiklewdi tastıyıqlaw',
        uz: 'Zaxira nusxadan tiklashni tasdiqlash',
        ru: 'Подтверждение восстановления из копии',
      );

  static String get confirmRestore => _pick(
        kaa: 'Tiklew',
        uz: 'Tiklash',
        ru: 'Восстановить',
      );

  static String restoreSummaryCounts(
    int subjects,
    int decks,
    int cards,
    int reviews,
    int images,
  ) =>
      _pick(
        kaa:
            'Pánler: $subjects • Toplamlar: $decks • Kartochkalar: $cards • Juwaplar tariyxı: $reviews • Súwretler: $images',
        uz:
            'Fanlar: $subjects • Toʻplamlar: $decks • Kartochkalar: $cards • Javoblar tarixi: $reviews • Rasmlar: $images',
        ru:
            'Предметов: $subjects • Колод: $decks • Карточек: $cards • Записей истории: $reviews • Изображений: $images',
      );

  static String get restoreExistingDataWarning => _pick(
        kaa:
            'Diqqat: Qosımshada ámeldegi maǵlıwmatlar bar. Bar maǵlıwmatlardı saqlap qosıwdı yamasa tolıq almastırıwdı tańlań:',
        uz:
            'Diqqat: Ilovada mavjud maʼlumotlar bor. Mavjud maʼlumotlarni saqlab qoʻshishni yoki toʻliq almashtirishni tanlang:',
        ru:
            'Внимание: В приложении уже есть данные. Выберите объединение с сохранением текущих данных или полную замену:',
      );

  static String get restoreModeMerge => _pick(
        kaa: 'Bar maǵlıwmatlardı saqlap qosıw',
        uz: 'Mavjudlarini saqlab qoʻshish',
        ru: 'Объединить (сохранить текущие)',
      );

  static String get restoreModeReplace => _pick(
        kaa: 'Tolıq almastırıw',
        uz: 'Toʻliq almashtirish',
        ru: 'Заменить все данные',
      );

  static String restoreSuccessSummary(int cards, int reviews, int images) =>
      _pick(
        kaa:
            'Tiklew juwmaqlandı: $cards kartochka, $reviews juwap tariyxı, $images súwret tiklendi.',
        uz:
            'Tiklash yakunlandi: $cards ta kartochka, $reviews ta javob tarixi, $images ta rasm tiklandi.',
        ru:
            'Восстановление завершено: карточек — $cards, записей истории — $reviews, изображений — $images.',
      );

  static String get errBackupExtension => _pick(
        kaa:
            'Jaramsız fayl túri. Tek «.json» formatındaǵı rezerv nusqa faylın tańlań.',
        uz:
            'Yaroqsiz fayl turi. Faqat «.json» formatidagi zaxira nusxa faylini tanlang.',
        ru:
            'Неверный тип файла. Выберите файл резервной копии в формате «.json».',
      );

  static String get errBackupCorruptedJson => _pick(
        kaa: 'Rezerv nusqa faylın oqıp bolmadı. JSON formatı zaqımlanǵan.',
        uz: 'Zaxira nusxa faylini oʻqib boʻlmadi. JSON formati shikastlangan.',
        ru: 'Не удалось прочитать файл резервной копии. Формат JSON повреждён.',
      );

  static String get errBackupInvalidSchema => _pick(
        kaa:
            'Rezerv nusqa quramı nadurıs yamasa májbúriy maydanlar jetispeydi.',
        uz:
            'Zaxira nusxa tuzilmasi notoʻgʻri yoki majburiy maydonlar yetishmaydi.',
        ru:
            'Некорректная структура резервной копии или отсутствуют обязательные поля.',
      );

  static String get errBackupNewerSchema => _pick(
        kaa:
            'Bul rezerv nusqa qosımshanıń jańaraq versiyasında jaratılǵan. Aldın qosımshanı jańalań.',
        uz:
            'Bu zaxira nusxa ilovaning yangiroq versiyasida yaratilgan. Avval ilovani yangilang.',
        ru:
            'Эта резервная копия создана в более новой версии приложения. Сначала обновите приложение.',
      );

  static String get errBackupBrokenRelationships => _pick(
        kaa:
            'Rezerv nusqadaǵı jazıwlar arasındaǵı baylanıslar (ID siltemeleri) buzılǵan.',
        uz:
            'Zaxira nusxadagi yozuvlar orasidagi bogʻlanishlar (ID havolalari) buzilgan.',
        ru:
            'Нарушены связи между записями (ссылки ID) в резервной копии.',
      );

  static String get errBackupCorruptedImages => _pick(
        kaa:
            'Rezerv nusqadaǵı súwret maǵlıwmatları zaqımlanǵan yamasa tabılmadı.',
        uz:
            'Zaxira nusxadagi rasm maʼlumotlari shikastlangan yoki topilmadi.',
        ru:
            'Данные изображений в резервной копии повреждены или отсутствуют.',
      );
}
