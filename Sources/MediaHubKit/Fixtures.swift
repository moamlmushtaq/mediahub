import Foundation

/// Sample data, shaped like the real thing.
///
/// WHY THIS SHIPS IN THE LIBRARY RATHER THAN IN A TEST TARGET
/// =========================================================
/// Three things need the same data and must not each invent their own:
/// SwiftUI previews, the snapshot tests that render screens to PNG in CI, and
/// the unit tests. When those drift, a preview looks right, a snapshot passes,
/// and the app is still wrong — which is precisely the failure this project has
/// already had twice.
///
/// The data is deliberately awkward. A fixture set of tidy records with every
/// field filled in produces screens that look wonderful in review and fall
/// apart on a real library, where a third of the files have no metadata match,
/// titles run to sixty characters, and ratings are missing. So: a long Arabic
/// title, a title with no artwork at all, a mixed Arabic/Latin name, a film
/// half-watched, and one finished.
public enum Fixtures {
    public static let viewer = Viewer(id: 3, slug: "moaml", name: "مؤمل")

    public static func card(
        id: String,
        name: String,
        original: String? = nil,
        type: MediaType = .movie,
        year: Int? = 2026,
        rating: Double? = 7.8,
        runtime: Int? = 118,
        overview: String = "",
        poster: String? = "/poster.jpg",
        backdrop: String? = "/backdrop.jpg",
        position: Double = 0,
        played: Bool = false
    ) -> MediaCard {
        MediaCard(
            id: id,
            name: name,
            originalTitle: original,
            type: type,
            year: year,
            communityRating: rating,
            officialRating: nil,
            runtimeMinutes: runtime,
            overview: overview,
            imageTags: ImageTags(primary: poster),
            backdropTag: backdrop,
            userData: UserItemData(
                played: played,
                playbackPosition: Ticks(seconds: position),
                playedPercentage: runtime.map { position / (Double($0) * 60) * 100 } ?? 0
            )
        )
    }

    /// A film with everything filled in — the easy case.
    public static let complete = card(
        id: "m1",
        name: "مشروع هيل ماري",
        original: "Project Hail Mary",
        rating: 8.7,
        runtime: 128,
        overview: """
        يستيقظ رايلاند غريس، مدرّس العلوم، على متن مركبة فضائية تبعد سنوات ضوئية عن \
        موطنه، فاقداً للذاكرة تماماً، لا يتذكّر من هو ولا كيف وصل إلى هناك. ومع عودة \
        ذاكرته تدريجياً، يبدأ في اكتشاف مهمّته: حلّ لغز المادة الغامضة التي تتسبّب في \
        انطفاء الشمس.
        """,
        position: 1_800
    )

    /// Half-watched, so the resume affordance has something to draw.
    public static let inProgress = card(
        id: "m2",
        name: "الطريق إلى الشمال",
        rating: 7.1,
        runtime: 104,
        overview: "رحلة عائلة عبر الصحراء بحثاً عن ماء.",
        position: 2_400
    )

    /// No metadata match at all. A real third of any personal library looks
    /// like this, and a design that has never been shown one will break on it.
    public static let bare = card(
        id: "m3",
        name: "Some.Release.2019.1080p.WEB-DL",
        year: nil,
        rating: nil,
        runtime: nil,
        overview: "",
        poster: nil,
        backdrop: nil
    )

    /// A title long enough to find out what the layout does about it.
    public static let longTitle = card(
        id: "m4",
        name: "الرحلة الطويلة نحو مدينة لا يعرف أحد اسمها بعد",
        rating: 6.4,
        runtime: 173,
        overview: "ملخّص قصير جداً."
    )

    public static let finished = card(
        id: "m5",
        name: "ليلة صامتة",
        rating: 9.1,
        runtime: 96,
        overview: "قصة تدور في ليلة واحدة.",
        position: 5_600,
        played: true
    )

    public static let series = card(
        id: "s1",
        name: "الحدود",
        original: "The Frontier",
        type: .series,
        rating: 8.2,
        runtime: nil,
        overview: "مسلسل من ثلاثة مواسم عن بلدة على الحدود."
    )

    public static let movies: [MediaCard] = [
        complete, inProgress, bare, longTitle, finished,
        card(id: "m6", name: "غبار", rating: 5.9, runtime: 88, overview: "قصة قصيرة."),
        card(id: "m7", name: "Interstellar", original: "Interstellar", rating: 8.6, runtime: 169,
             overview: "A team travels through a wormhole."),
        card(id: "m8", name: "المدينة الأخيرة", rating: 7.4, runtime: 121, overview: "بعد النهاية."),
    ]

    public static let allSeries: [MediaCard] = [
        series,
        card(id: "s2", name: "خط الأفق", type: .series, rating: 7.7, runtime: nil, overview: "موسمان."),
        card(id: "s3", name: "Night Shift", type: .series, rating: 8.0, runtime: nil, overview: "Hospital drama."),
    ]

    public static let rails: [Rail] = [
        Rail(key: "resume", title: "تابع المشاهدة", items: [complete, inProgress]),
        Rail(key: "movies", title: "أحدث الأفلام", items: movies),
        Rail(key: "series", title: "أحدث المسلسلات", items: allSeries),
    ]

    public static let genres: [Genre] = [
        Genre(id: "1", name: "دراما"),
        Genre(id: "2", name: "إثارة"),
        Genre(id: "3", name: "خيال علمي"),
        Genre(id: "4", name: "كوميديا"),
    ]

    public static let home = Home(rails: rails, genres: genres)

    public static let people: [Person] = [
        Person(id: "p1", name: "ريان غوسلينغ", role: "رايلاند غريس", type: "Actor", imageTag: "/p1.jpg"),
        Person(id: "p2", name: "فيل لورد", role: "Director", type: "Director", imageTag: nil),
        Person(id: "p3", name: "سانديب موديل", role: "Writer", type: "Writer", imageTag: "/p3.jpg"),
    ]

    public static let detail = MediaDetail(
        card: complete,
        genres: ["خيال علمي", "دراما", "مغامرة"],
        studios: ["Amblin", "MGM"],
        people: people,
        tagline: "الأمل الأخير للبشرية يقع على عاتق رجل واحد.",
        mediaSources: [
            MediaSource(id: "f1", path: "/Movies/Project.Hail.Mary.2026/movie.mp4",
                        container: "mp4", size: 8_120_000_000)
        ]
    )

    public static let seasons: [Season] = [
        Season(id: "n1-1", name: "الموسم الأول", indexNumber: 1, imageTag: "/s1.jpg", episodeCount: 8),
        Season(id: "n1-2", name: "الموسم الثاني", indexNumber: 2, imageTag: "/s2.jpg", episodeCount: 10),
    ]

    public static let episodes: [Episode] = [
        Episode(id: "e1", name: "البداية", indexNumber: 1, seasonNumber: 1,
                overview: "تبدأ القصة في ليلة ممطرة.", runtimeMinutes: 52,
                imageTag: "/e1.jpg", userData: UserItemData(playbackPosition: Ticks(seconds: 900))),
        Episode(id: "e2", name: "ما بعد الجسر", indexNumber: 2, seasonNumber: 1,
                overview: "", runtimeMinutes: 48, imageTag: nil, userData: UserItemData()),
        Episode(id: "e3", name: "حلقة بعنوان طويل بما يكفي ليلتف على سطرين على الأقل",
                indexNumber: 3, seasonNumber: 1,
                overview: "ملخّص طويل يشرح ما حدث في الحلقة السابقة ثم يمهّد لما بعدها بتفصيل.",
                runtimeMinutes: 55, imageTag: "/e3.jpg",
                userData: UserItemData(played: true, playbackPosition: Ticks(seconds: 3_290))),
    ]

    public static let subtitles: [SubtitleTrack] = [
        SubtitleTrack(url: "https://cdn.invalid/ara.srt", language: "ara",
                      label: "العربية", forced: false, isDefault: true),
        SubtitleTrack(url: "https://cdn.invalid/ara.forced.srt", language: "ara",
                      label: "العربية (علامات)", forced: true, isDefault: false),
        SubtitleTrack(url: "https://cdn.invalid/eng.srt", language: "eng",
                      label: "English", forced: false, isDefault: false),
    ]
}
