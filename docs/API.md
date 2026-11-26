# API сайту, з яким працює застосунок

Застосунок — «тонкий клієнт»: усе, що він показує, береться з сайту за адресою `https://<сайт>/api/app/v1/*` (код сервера —
у репозиторії сайту церкви, він закритий; тут — контракт). Усі відповіді — JSON (UTF-8). Точні поля — у розборі
`lib/api/models.dart` і `lib/api/songbook_models.dart`: застосунок терпимий до відсутніх полів (проповідь без поля не падає).
Кожна вдала відповідь застосунок зберігає на телефоні й показує з диска, коли мережі немає.

Адреса сайту — константа `Api.siteUrl` у `lib/api/api.dart` (і `ENDPOINT` у `ContentAlerts.kt`, `DEFAULT_ENDPOINT` у `LiveAlerts.kt`).

## Дані

| Запит | Що віддає |
| --- | --- |
| `GET /config[?lang=ru\|en]` | усе про церкву на старті: `church` (назва, логотип), `contacts`, `service` (час богослужіння), `siteUrl`, `verses` (вірші дня), `live` (ефір: `enabled`, `endpoint`, `channelUrl`, тексти заглушки), `donation` (реквізити, `pageUrl`, `onlinePayment`). Мова — `lang`; чого нема в словнику — українською |
| `GET /sermons` | уся фонотека одним списком (без описів): `sermons[]` (`id`, `title`, `preacher`, `date`, `duration`, `audioUrl`, `coverUrl`, `books`, `topics`, `isReading`, `url`, `videoId`) + довідники `preachers`, `books`, `topics`. Застосунок фільтрує сам, у тому числі без мережі |
| `GET /sermons/{id}` | опис проповіді, інформація про проповідника, `byPreacher`, `byBook` («схожі») |
| `GET /videos`, `GET /videos/{kind}/{slug}` | відео з каналу YouTube церкви: останні й розділи (проповідники, серії, книги Біблії); ролики розділу |
| `GET /news?section=…`, `GET /news/{slug}` | новини, статті, фотозвіти без тексту; текст статті (`html`, `gallery`, `videoId`, `documentUrl`) |
| `GET /bible` | `translations`, `defaults`, `start`, адреса словника; `GET /bible/{translation}` — книги (`bookNr`, `slug`, `name`, `chapters`); `GET /bible/{translation}/{bookNr}/{chapter}[?parallel=…&commentaries=1]` — вірші, аудіо (`verseStarts` — початки віршів у секундах), коментарі, сусідні глави; `GET /bible/search?q=&t=` — пошук |
| `GET /songbook` | збірники, їхні налаштування, звуковий банк для синтезатора (`soundfontUrl`); `GET /songbook/{збірник}[?full=1]` — пісні (з `full=1` — з текстами й медіа для роботи без мережі); `GET /songbook/{збірник}/{номер}`; `…/search?q=` |
| `GET /sheet-music?page=&limit=` | ноти сторінками: `items[]` (`slug`, `title`, `collection`, `pages`, `files`, джерело й ліцензія), `total`, `collections` |
| `GET /search?q=&limit=` | пошук по всьому: проповіді, новини й статті, пісні |
| `GET /latest` | по 10 найсвіжіших записів кожного розділу — для сповіщень «є нове» (відео, що йде наживо, позначене `live`) |

Окремо від `/api/app/v1`: `GET /api/live` (`live`, `nextInMs` — через скільки питати знову; у вікні трансляції — раз на 30 с, поза ним — рідко) і
`GET /api/bible/dictionary?q=` (словникова стаття). Звук проповідей — `mp3` із підтримкою `Range`, звукові банки — `/uploads/soundfonts/*.sf3`.

## Оновлення застосунку

| Запит | Що віддає |
| --- | --- |
| `GET /update?platform=android&version=X.Y.Z` | `latest` (`version`, `notes`, `publishedAt`, `size`, `sha256`, `downloadUrl`) і `updateAvailable`. Це **запасна дорога**: з 1.0.15 застосунок питає GitHub напряму (`https://api.github.com/repos/<UPDATE_REPO>/releases/latest`), а сайт лише дублює його для старих копій і для випадку, коли GitHub недоступний |
| `GET /update/apk` | переадресація (302) на файл останнього випуску |

## Сповіщення

Без Firebase застосунок сам будить себе: `LiveAlerts.kt` питає `/api/live` за будильником (сайт у `alert.nextCheckInMs` каже, коли питати
знову), `ContentAlerts.kt` раз на годину питає `/latest` і порівнює з тим, що вже бачив. З Firebase Cloud Messaging (за наявності
`google-services.json` у збірці й правила `keep` для ресурсів `fcm_*`) телефон підписується на теми `live`, `sermons`, `news`, `videos` — ті самі, що й перемикачі «Сповіщення»;
повідомлення — лише сигнал «перевір зараз», показує його той самий код. У готових випусках 1.0.13–1.0.15 FCM у APK не вмикається (див. [опис, «Відомі особливості»](ПОВНИЙ-ОПИС.md#обмеження-й-відомі-особливості)) — працюють будильники.

## Свій сервер

Достатньо віддавати перелічене вище з тими самими іменами полів. Застосунок питає `/config` на старті, решта — коли
людина відкриває відповідний розділ; розділ, який сервер не віддає, покаже повідомлення про помилку.
