import Testing
@testable import LadCore

@Suite("Transliteration")
struct TransliteratorTests {
    /// Examples from the 2010 resolution and its table.
    @Test("Official examples", arguments: [
        ("Алушта", "Alushta"), ("Андрій", "Andrii"), ("Борщагівка", "Borshchahivka"), ("Вінниця", "Vinnytsia"),
        ("Гадяч", "Hadiach"), ("Згорани", "Zghorany"), ("Розгон", "Rozghon"), ("Ґалаґан", "Galagan"),
        ("Донецьк", "Donetsk"), ("Рівне", "Rivne"), ("Олег", "Oleh"), ("Єнакієве", "Yenakiieve"),
        ("Гаєвич", "Haievych"), ("Короп'є", "Koropie"), ("Житомир", "Zhytomyr"), ("Закарпаття", "Zakarpattia"),
        ("Їжакевич", "Yizhakevych"), ("Кадиївка", "Kadyivka"), ("Мар'їне", "Marine"), ("Йосипівка", "Yosypivka"),
        ("Стрий", "Stryi"), ("Олексій", "Oleksii"), ("Київ", "Kyiv"), ("Харків", "Kharkiv"),
        ("Біла Церква", "Bila Tserkva"), ("Чернівці", "Chernivtsi"), ("Шостка", "Shostka"),
        ("Щербухи", "Shcherbukhy"), ("Гоща", "Hoshcha"), ("Юрій", "Yurii"), ("Корюківка", "Koriukivka"),
        ("Яготин", "Yahotyn"), ("Костянтин", "Kostiantyn"), ("Знам'янка", "Znamianka"), ("Феодосія", "Feodosiia"),
        ("Ужгород", "Uzhhorod"), ("Олег Фостяк", "Oleh Fostiak"),
    ])
    func officialExamples(ukrainian: String, latin: String) {
        #expect(Transliterator.ukrainianToLatin(ukrainian) == latin)
    }

    @Test("Capitals, punctuation and other characters")
    func keepsTheRest() {
        #expect(Transliterator.ukrainianToLatin("ЩУКА") == "SHCHUKA")
        #expect(Transliterator.ukrainianToLatin("Щука") == "Shchuka")
        #expect(Transliterator.ukrainianToLatin("Привіт, світ! 2026") == "Pryvit, svit! 2026")
        #expect(Transliterator.ukrainianToLatin("сімʼя та «м’ята»") == "simia ta «miata»")
        #expect(Transliterator.ukrainianToLatin("'цитата'") == "'tsytata'")
    }

    @Test("An apostrophe used as an opening quote starts a word")
    func readsOpeningQuotes() {
        #expect(Transliterator.ukrainianToLatin("'Яна'") == "'Yana'")
        #expect(Transliterator.ukrainianToLatin("кажу 'Юля'") == "kazhu 'Yulia'")
        #expect(Transliterator.ukrainianToLatin("п'ять 'ялинок'") == "piat 'yalynok'")
    }

    @Test("Text without Ukrainian letters is not transliterated")
    func needsUkrainian() {
        #expect(Transliterator.ukrainianToLatin("hello 123") == nil)
        #expect(Transliterator.ukrainianToLatin("") == nil)
    }
}

@Suite("Case cycle")
struct CaseCycleTests {
    @Test("lowercase → UPPERCASE → Title Case → lowercase")
    func cycles() {
        #expect(CaseCycle.next("привіт світ") == "ПРИВІТ СВІТ")
        #expect(CaseCycle.next("ПРИВІТ СВІТ") == "Привіт Світ")
        #expect(CaseCycle.next("Привіт Світ") == "привіт світ")
        #expect(CaseCycle.next("hello World") == "hello world")
    }

    @Test("Apostrophes, hyphens and one-letter words")
    func handlesEdges() {
        #expect(CaseCycle.next("М'ЯТА") == "М'ята")
        #expect(CaseCycle.next("ПО-УКРАЇНСЬКИ") == "По-українськи")
        #expect(CaseCycle.next("A") == "a")
        #expect(CaseCycle.next("123 !") == nil)
    }

    @Test("Title case starts words after brackets and quotes, not after digits")
    func titleCasesWordStarts() {
        #expect(CaseCycle.next("2ND (HELLO) «СВІТ»") == "2nd (Hello) «Світ»")
    }
}
