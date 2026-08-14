using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.System;
using Toybox.Lang;
using Toybox.Math;

// Pole danych: ile zlotych zaoszczedzilem, jadac rowerem zamiast autem.
//
//     oszczednosc = dystans[km] / 100 * spalanie[l/100km] * cena[zl/l]
//
// Cena benzyny 95 pochodzi z internetu (PriceFetcher / PriceService), a gdy
// jeszcze nic nie pobrano - z ustawienia "cena awaryjna".
//
// Rysujemy wszystko sami (onUpdate), bo uklad musi sie miescic zarowno
// w malym kaflu 1/4 ekranu, jak i na calym ekranie.
class SpalanieView extends WatchUi.DataField {

    hidden var mSpalanie as Lang.Float = Config.DEFAULT_SPALANIE;
    hidden var mCel as Lang.Float = Config.DEFAULT_CEL;   // 0 = bez paska
    hidden var mCena as Lang.Float = Config.DEFAULT_CENA;
    hidden var mZSieci as Lang.Boolean = false;
    hidden var mDataCeny as Lang.String? = null;
    hidden var mBlad as Lang.String? = null;

    hidden var mKm as Lang.Float = 0.0;
    hidden var mLitry as Lang.Float = 0.0;
    hidden var mZlote as Lang.Float = 0.0;

    hidden var mFetcher as PriceFetcher?;
    hidden var mLicznik as Lang.Number = 0;

    // Geometria kafla i tarczy - wypelniana raz na klatke w ustawGeometrie().
    // Na okraglym zegarku kafel to prostokat, ale WIDAC z niego tylko to, co
    // wpada w kolo; te pola opisuja wlasnie to kolo w ukladzie kafla.
    hidden var mH as Lang.Number = 0;
    hidden var mCx as Lang.Number = 0;
    hidden var mCy as Lang.Number = 0;      // srodek tarczy w ukladzie kafla
    hidden var mR as Lang.Number = 0;       // promien obszaru dla tekstu
    hidden var mPolW as Lang.Number = 0;    // polowa szerokosci kafla
    hidden var mKolo as Lang.Boolean = false;
    hidden var mLuk as Lang.Boolean = false;
    hidden var mRLuku as Lang.Number = 0;   // promien sciezki luku postepu
    hidden var mGrubosc as Lang.Number = 8; // grubosc luku

    hidden var mEtykieta as Lang.String = "PLN";
    hidden var mZl as Lang.String = "zl";
    hidden var mZlL as Lang.String = "zl/l";
    hidden var mL as Lang.String = "l";
    hidden var mKgCo2 as Lang.String = "kg CO2";

    function initialize() {
        DataField.initialize();
        wczytajTeksty();
        wczytajUstawienia();
        odczytajCene();
    }

    // --- dane ------------------------------------------------------------

    function compute(info as Activity.Info) as Void {
        var m = 0.0;
        if (info has :elapsedDistance && info.elapsedDistance != null) {
            m = info.elapsedDistance;
        }
        mKm = m / 1000.0;
        mLitry = mKm * mSpalanie / 100.0;
        mZlote = mLitry * mCena;

        // Storage czytamy co ~15 s, a nie co sekunde - szkoda pradu i czasu
        mLicznik = mLicznik + 1;
        if (mLicznik % 15 == 0) {
            odczytajCene();
            // spalanie i cel tez moga przyjsc z pobranego pliku, wiec
            // odswiezamy je razem z cena - zmiana zadziala jeszcze w tej jezdzie
            wczytajUstawienia();
            sprobujPobrac();
        }
        if (mLicznik == 3) {
            // pierwsza proba tuz po starcie treningu, gdy telefon jest w zasiegu
            sprobujPobrac();
        }
    }

    // Proba pobrania z poziomu treningu - traktowana jako dodatek do uslugi
    // w tle. Jesli sie nie uda (brak telefonu, brak zgody), po prostu zostaje
    // ostatnia zapisana cena.
    hidden function sprobujPobrac() as Void {
        if (!PriceStore.trzebaOdswiezyc()) {
            return;
        }
        if (mFetcher == null) {
            mFetcher = new PriceFetcher(false);
        }
        if (mFetcher.zajety()) {
            return;
        }
        try {
            mFetcher.pobierz();
        } catch (e) {
            // niektore urzadzenia nie pozwalaja polom danych siegac do sieci
            mFetcher = null;
        }
    }

    hidden function odczytajCene() as Void {
        mCena = PriceStore.cena();
        mZSieci = PriceStore.zSieci();
        mDataCeny = PriceStore.dataCeny();
        mBlad = PriceStore.blad();
    }

    hidden function wczytajUstawienia() as Void {
        // Kolejnosc zrodel rozstrzyga PriceStore: pobrany plik > telefon > Config.
        mSpalanie = PriceStore.spalanie();
        mCel = PriceStore.cel();
    }

    hidden function wczytajTeksty() as Void {
        try {
            mEtykieta = WatchUi.loadResource(Rez.Strings.FieldLabel);
            mZl = WatchUi.loadResource(Rez.Strings.UnitZl);
            mZlL = WatchUi.loadResource(Rez.Strings.UnitZlL);
            mL = WatchUi.loadResource(Rez.Strings.UnitL);
            mKgCo2 = WatchUi.loadResource(Rez.Strings.UnitKgCo2);
        } catch (e) {
        }
    }

    function onSettingsChanged() as Void {
        wczytajUstawienia();
        odczytajCene();
    }

    // --- rysowanie -------------------------------------------------------

    function onUpdate(dc as Graphics.Dc) as Void {
        var tlo = getBackgroundColor();
        dc.setColor(tlo, tlo);
        dc.clear();

        var kolor = (tlo == Graphics.COLOR_BLACK)
            ? Graphics.COLOR_WHITE
            : Graphics.COLOR_BLACK;
        var koloSzary = (tlo == Graphics.COLOR_BLACK)
            ? Graphics.COLOR_LT_GRAY
            : Graphics.COLOR_DK_GRAY;

        var w = dc.getWidth();
        var h = dc.getHeight();
        var maleH = dc.getFontHeight(Graphics.FONT_XTINY);

        // Kwota jest najwazniejsza. Etykiete, wskaznik i stopke dokladamy tylko
        // wtedy, gdy PO ich odjeciu zostaje na nia przynajmniej tyle, ile
        // zajmuje FONT_MEDIUM - inaczej na niskim kaflu (280x69, 280x49)
        // ozdoby zjadlyby miejsce i glowna liczba zrobilaby sie mikroskopijna.
        // Ten sam kod obsluguje wiec i caly ekran (280x280), i pasek 280x49.
        var minKwota = dc.getFontHeight(Graphics.FONT_MEDIUM);

        var udzial = 0.0;
        if (mCel > 0.0) {
            udzial = mZlote / mCel;
            if (udzial > 1.0) { udzial = 1.0; }
            if (udzial < 0.0) { udzial = 0.0; }
        }
        var celOsiagniety = (mCel > 0.0) && (mZlote >= mCel);

        ustawGeometrie(w, h);

        // Luk postepu zjada obrzeze tarczy, wiec liczymy go PRZED tekstem -
        // to on wyznacza promien, w ktorym musza sie zmiescic napisy.
        if (mLuk) {
            rysujLuk(dc, udzial, tlo);
        }

        var gora = mKolo ? (mCy - mR) : 0;
        var dol  = mKolo ? (mCy + mR) : h;
        if (gora < 0) { gora = 0; }
        if (dol > h) { dol = h; }

        // Etykieta u gory: najpierw probujemy przy samej krawedzi obszaru,
        // a dopiero gdy cieciwa tarczy jest tam za waska - zjezdzamy do
        // pierwszego wiersza, w ktorym napis sie miesci. Odwrotna kolejnosc
        // (zawsze licz z cieciwy) marnowalaby wysokosc w waskich kaflach.
        var etykW = dc.getTextWidthInPixels(mEtykieta, Graphics.FONT_XTINY);
        var yEtyk = gora;
        if (etykW > 2 * polSzerokosci(yEtyk, maleH)) {
            yEtyk = yWiersza(etykW, maleH, true);
            if (yEtyk < gora) { yEtyk = gora; }
        }
        if (etykW <= 2 * polSzerokosci(yEtyk, maleH)
                && (dol - (yEtyk + maleH) >= minKwota)) {
            dc.setColor(koloSzary, Graphics.COLOR_TRANSPARENT);
            dc.drawText(mCx, yEtyk, Graphics.FONT_XTINY, mEtykieta,
                        Graphics.TEXT_JUSTIFY_CENTER);
            gora = yEtyk + maleH;
        }

        // Stopka: cena i dzien, z ktorego pochodzi. Im dluzszy wariant, tym
        // wyzej musi usiasc, zeby zmiescic sie w cieciwie - wiec wysokosc
        // dobieramy razem z trescia, biorac pierwszy wariant, ktory wchodzi.
        var warianty = stopkaWarianty();
        for (var i = 0; i < warianty.size(); i++) {
            var tekst = warianty[i];
            var szer = dc.getTextWidthInPixels(tekst, Graphics.FONT_XTINY);
            var y = dol - maleH;                        // patrz uwaga przy etykiecie
            if (szer > 2 * polSzerokosci(y, maleH)) {
                y = yWiersza(szer, maleH, false);
                if (y > dol - maleH) { y = dol - maleH; }
            }
            if (szer <= 2 * polSzerokosci(y, maleH) && (y - gora >= minKwota)) {
                var kolorStopki = koloSzary;
                if (!mZSieci) {
                    kolorStopki = (tlo == Graphics.COLOR_BLACK)
                        ? Graphics.COLOR_YELLOW
                        : Graphics.COLOR_ORANGE;
                }
                dc.setColor(kolorStopki, Graphics.COLOR_TRANSPARENT);
                dc.drawText(mCx, y, Graphics.FONT_XTINY, tekst,
                            Graphics.TEXT_JUSTIFY_CENTER);
                dol = y - 2;            // wlos odstepu, zeby wiersze nie skleily sie
                break;
            }
        }

        // Pasek postepu prosty - tylko tam, gdzie luk nie ma sensu, czyli
        // w waskim kaflu (luk potrzebuje calej tarczy).
        var paskH = h / 14;
        if (paskH < 5) { paskH = 5; }
        if (paskH > 10) { paskH = 10; }
        if (!mLuk && mCel > 0.0 && (dol - gora - paskH - 6 >= minKwota)) {
            var by = dol - paskH - 3;
            var polB = polSzerokosci(by, paskH) - 4;
            if (polB > paskH) {
                var bx = mCx - polB;
                var bw = 2 * polB;
                var promien = paskH / 2;

                dc.setColor(
                    (tlo == Graphics.COLOR_BLACK) ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(bx, by, bw, paskH, promien);

                var wypelnienie = (bw * udzial).toNumber();
                if (wypelnienie > 0) {
                    if (wypelnienie < paskH) { wypelnienie = paskH; }
                    dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(bx, by, wypelnienie, paskH, promien);
                }
                dol = by - 3;
            }
        }

        // drugi wiersz: ile litrow paliwa i ile CO2 nie poszlo w powietrze.
        // Dystansu ani czasu tu nie dubluje - te sa na kazdym innym ekranie;
        // to ma pokazywac to, czego nie widac nigdzie indziej.
        if (dol - gora - maleH >= minKwota) {
            var yWiersz = dol - maleH;
            var polR = polSzerokosci(yWiersz, maleH);
            var litryTxt = kropkaNaPrzecinek(mLitry.format("%.1f")) + " " + mL;
            var co2Txt = kropkaNaPrzecinek((mLitry * Config.CO2_NA_LITR).format("%.1f"))
                         + " " + mKgCo2;
            // kazdy napis dostaje polowe dostepnej cieciwy, nie polowe kafla
            var mieszczaSie =
                dc.getTextWidthInPixels(litryTxt, Graphics.FONT_XTINY) <= polR - 4
                && dc.getTextWidthInPixels(co2Txt, Graphics.FONT_XTINY) <= polR - 4;
            if (mieszczaSie) {
                dc.setColor(koloSzary, Graphics.COLOR_TRANSPARENT);
                dc.drawText(mCx - polR / 2, yWiersz, Graphics.FONT_XTINY, litryTxt,
                            Graphics.TEXT_JUSTIFY_CENTER);
                dc.drawText(mCx + polR / 2, yWiersz, Graphics.FONT_XTINY, co2Txt,
                            Graphics.TEXT_JUSTIFY_CENTER);
                dol = yWiersz;
            }
        }

        // glowna wartosc - na zielono, gdy cel przejazdu dowieziony
        rysujKwote(dc, gora, dol, celOsiagniety ? Graphics.COLOR_GREEN : kolor);
    }

    // --- geometria okraglej tarczy ---------------------------------------

    // Pole danych widzi tylko swoj kafel i NIE wie, gdzie on lezy na ekranie.
    // Jedyna podpowiedz to getObscurityFlags(): ktore krawedzie kafla tarcza
    // przycina. W jednym przypadku - kafla na caly ekran - to wystarcza, zeby
    // odtworzyc kolo w ukladzie wspolrzednych kafla, a wiec zeby przestac
    // pisac po rogach, ktorych i tak nie widac (kwadrat 280x280 ma 78 000
    // pikseli, wpisane w niego kolo tarczy tylko 61 000).
    hidden function ustawGeometrie(w as Lang.Number, h as Lang.Number) as Void {
        mH = h;
        mCx = w / 2;
        mCy = h / 2;
        mPolW = w / 2 - 2;
        mR = mPolW;
        mKolo = false;
        mLuk = false;

        if (!(System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND)) {
            return;
        }

        // Kolo odtwarzamy TYLKO dla kafla na caly ekran, czyli gdy tarcza
        // przycina wszystkie cztery jego krawedzie. Wtedy - i tylko wtedy -
        // wiadomo na pewno, ze srodek kola lezy w srodku kafla, a promien to
        // polowa jego szerokosci.
        // Dla waskiego pasa tej pewnosci nie ma: OBSCURE_TOP mowi tylko, ze
        // gorne rogi pasa sa sciete, a nie o ile pas jest odsuniety od gory
        // ekranu - a bez tego srodka kola nie da sie umiejscowic. Zgadywanie
        // konczy sie tekstem wypchnietym poza kafel, wiec w pasach zostajemy
        // przy prostokacie (tak jak bylo do tej pory i jak dziala dobrze).
        var f = getObscurityFlags();
        var caly = ((f & WatchUi.DataField.OBSCURE_LEFT) != 0)
                && ((f & WatchUi.DataField.OBSCURE_RIGHT) != 0)
                && ((f & WatchUi.DataField.OBSCURE_TOP) != 0)
                && ((f & WatchUi.DataField.OBSCURE_BOTTOM) != 0);
        if (!caly) {
            return;
        }

        var rEkranu = (w < h) ? (w / 2) : (h / 2);
        mKolo = true;
        mLuk = (mCel > 0.0) && (rEkranu >= 60);

        if (mLuk) {
            mGrubosc = rEkranu / 11;
            if (mGrubosc < 6) { mGrubosc = 6; }
            if (mGrubosc > 16) { mGrubosc = 16; }
            mRLuku = rEkranu - mGrubosc / 2 - 4;
            mR = rEkranu - mGrubosc - 8;
        } else {
            mR = rEkranu - 4;
        }
    }

    // Polowa szerokosci dostepnej w wierszu [y, y+wys): na okraglej tarczy to
    // polowa cieciwy w NAJWEZSZYM miejscu tego wiersza, czyli przy tej jego
    // krawedzi, ktora lezy dalej od srodka tarczy.
    hidden function polSzerokosci(y as Lang.Number, wys as Lang.Number) as Lang.Number {
        if (!mKolo) {
            return mPolW;
        }
        var d1 = (y - mCy).abs();
        var d2 = (y + wys - mCy).abs();
        var d = (d1 > d2) ? d1 : d2;
        if (d >= mR) {
            return 0;
        }
        return Math.sqrt(mR * mR - d * d).toNumber();
    }

    // Odwrotnosc powyzszego: najwyzszy (gora = true) albo najnizszy wiersz
    // o wysokosci `wys`, w ktorym miesci sie jeszcze tekst szerokosci `szer`.
    hidden function yWiersza(szer as Lang.Number, wys as Lang.Number,
                             gora as Lang.Boolean) as Lang.Number {
        if (!mKolo) {
            return gora ? 0 : (mH - wys);
        }
        var pol = szer / 2 + 2;
        if (pol >= mR) {
            return mCy - wys / 2;       // i tak sie nie zmiesci - srodek tarczy
        }
        var dy = Math.sqrt(mR * mR - pol * pol).toNumber();
        return gora ? (mCy - dy) : (mCy + dy - wys);
    }

    // Postep jako polkole po dolnej krawedzi tarczy: od 9:00, przez 6:00, do
    // 3:00. Kat 0 to 3:00, rosnie przeciwnie do wskazowek zegara, wiec dolna
    // polowke rysujemy od 180 do 360 W KIERUNKU PRZECIWNYM. Na okraglym
    // ekranie to jedyne miejsce, gdzie duzy wskaznik nie zabiera pola liczbie.
    hidden function rysujLuk(dc as Graphics.Dc, udzial as Lang.Float, tlo) as Void {
        dc.setPenWidth(mGrubosc);

        dc.setColor((tlo == Graphics.COLOR_BLACK)
                        ? Graphics.COLOR_DK_GRAY
                        : Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_TRANSPARENT);
        dc.drawArc(mCx, mCy, mRLuku, Graphics.ARC_COUNTER_CLOCKWISE, 180, 359);

        if (udzial > 0.0) {
            var koniec = 180 + (179.0 * udzial).toNumber();
            if (koniec < 184) { koniec = 184; }   // zeby drgnal juz przy pierwszych metrach
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(mCx, mCy, mRLuku, Graphics.ARC_COUNTER_CLOCKWISE, 180, koniec);
        }
        dc.setPenWidth(1);
    }

    // Duza kwota zlozona z dwoch kawalkow: calosc grubym fontem CYFROWYM,
    // a koncowka z przecinkiem i "zl" mniejszym fontem tekstowym, przyklejona
    // do dolnej krawedzi. Fonty FONT_NUMBER_* sa duzo wieksze od tekstowych,
    // ale maja tylko cyfry - stad ten podzial zamiast rezygnacji z nich.
    hidden function rysujKwote(dc as Graphics.Dc, gora as Lang.Number,
                               dol as Lang.Number, kolor) as Void {
        var s = kwota(mZlote);
        var i = s.find(",");
        var duzy = (i == null) ? s : s.substring(0, i);
        var maly = ((i == null) ? "" : s.substring(i, s.length())) + " " + mZl;

        var maxH = dol - gora;
        var srodekY = gora + maxH / 2;

        // Od najwiekszego. THAI_HOT to najgrubszy font cyfrowy w systemie -
        // na calym ekranie 6X wchodzi dopiero teraz, gdy pasek postepu
        // przeniosl sie z dolu tarczy na jej obrzeze.
        var duzeFonty = [
            Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD
        ];
        for (var k = 0; k < duzeFonty.size(); k++) {
            var fd = duzeFonty[k];
            var hd = dc.getFontHeight(fd);
            if (hd > maxH) {
                continue;
            }
            // Szerokosc bierzemy z cieciwy na wysokosci SAMEJ liczby, a nie
            // calego pasma - im wiekszy font, tym wezsze ma tam miejsce.
            var maxW = 2 * polSzerokosci(srodekY - hd / 2, hd) - 4;

            var fm;
            if (hd >= 80) {
                fm = Graphics.FONT_MEDIUM;
            } else if (hd >= 44) {
                fm = Graphics.FONT_SMALL;
            } else {
                fm = Graphics.FONT_XTINY;
            }
            var wd = dc.getTextWidthInPixels(duzy, fd);
            var wm = dc.getTextWidthInPixels(maly, fm);
            if (wd + wm > maxW) {
                continue;
            }
            var x0 = mCx - (wd + wm) / 2;
            dc.setColor(kolor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0, srodekY, fd, duzy,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            // Fonty FONT_NUMBER_* maja pod cyframi spory pusty pas (miejsce na
            // ogonki, ktorych nie uzywaja). Bez tej poprawki koncowka ",34 zl"
            // odjezdza wyraznie ponizej dolu cyfr i uklad sie rozjezdza.
            dc.drawText(x0 + wd, srodekY + hd / 2 - dc.getFontHeight(fm) - hd / 6,
                        fm, maly, Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }

        // Kafel za maly na font cyfrowy - caly napis jednym fontem tekstowym.
        var tekst = s + " " + mZl;
        var font = dobierzFont(dc, tekst, 2 * polSzerokosci(gora, maxH) - 4, maxH);
        dc.setColor(kolor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mCx, srodekY, font, tekst,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "12,34" / "123,4" / "1234"
    hidden function kwota(v as Lang.Float) as Lang.String {
        var s;
        if (v < 100.0) {
            s = v.format("%.2f");
        } else if (v < 1000.0) {
            s = v.format("%.1f");
        } else {
            s = v.format("%.0f");
        }
        return kropkaNaPrzecinek(s);
    }

    hidden function kropkaNaPrzecinek(s as Lang.String) as Lang.String {
        var i = s.find(".");
        if (i == null) {
            return s;
        }
        return s.substring(0, i) + "," + s.substring(i + 1, s.length());
    }

    // Stopka w trzech dlugosciach, od najpelniejszej. Font XTINY jest
    // najmniejszy jaki mamy, wiec jedyne, co mozna skracac, to sam tekst.
    //   pelna:   "7,25 zl/l 09.08"
    //   srednia: "7,25 09.08"
    //   krotka:  "7,25"
    // Przy cenie awaryjnej sufiksem jest "?", ale i tak sygnalizuje ja kolor,
    // wiec w najkrotszym wariancie mozna go poswiecic.
    // Wybor nalezy do onUpdate: na okraglej tarczy dluzszy wariant musi usiasc
    // wyzej, wiec o tresci i wysokosci trzeba decydowac razem.
    hidden function stopkaWarianty() as Lang.Array<Lang.String> {
        var cenaTxt = kropkaNaPrzecinek(mCena.format("%.2f"));

        var sufiks = "?";
        if (mZSieci && mDataCeny != null && mDataCeny.length() >= 10) {
            sufiks = mDataCeny.substring(8, 10) + "." + mDataCeny.substring(5, 7);
        } else if (mBlad != null) {
            sufiks = mBlad;
        }

        return [
            cenaTxt + " " + mZlL + " " + sufiks,
            cenaTxt + " " + sufiks,
            cenaTxt
        ];
    }

    // najwiekszy font, w ktorym tekst zmiesci sie w kafelku
    hidden function dobierzFont(dc as Graphics.Dc, tekst as Lang.String,
                                maxW as Lang.Number, maxH as Lang.Number) {
        // Swiadomie NIE uzywamy fontow FONT_NUMBER_*: nie maja liter ("zl")
        // ani pewnego przecinka, wiec tekst by sie posypal.
        var fonty = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];
        for (var i = 0; i < fonty.size(); i++) {
            var f = fonty[i];
            if (dc.getTextWidthInPixels(tekst, f) <= maxW
                    && dc.getFontHeight(f) <= maxH) {
                return f;
            }
        }
        return Graphics.FONT_XTINY;
    }
}
