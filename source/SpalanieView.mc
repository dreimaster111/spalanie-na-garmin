using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Activity;
using Toybox.System;
using Toybox.Lang;

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

    hidden var mEtykieta as Lang.String = "PLN";
    hidden var mZl as Lang.String = "zl";
    hidden var mZlL as Lang.String = "zl/l";

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

        // Kwota jest najwazniejsza. Etykiete, pasek i stopke dokladamy tylko
        // wtedy, gdy PO ich odjeciu zostaje na nia przynajmniej tyle, ile
        // zajmuje FONT_MEDIUM - inaczej na niskim kaflu (280x69, 280x49)
        // ozdoby zjadlyby miejsce i glowna liczba zrobilaby sie mikroskopijna.
        // Ten sam kod obsluguje wiec i caly ekran (280x280), i pasek 280x49.
        var minKwota = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var paskH = h / 14;
        if (paskH < 5) { paskH = 5; }
        if (paskH > 10) { paskH = 10; }

        var gora = 0;
        var dol = h;

        // etykieta u gory - tylko jesli miesci sie tez w POZIOMIE
        var zEtykieta = (dc.getTextWidthInPixels(mEtykieta, Graphics.FONT_XTINY) <= w - 4)
                        && (h - maleH >= minKwota);
        if (zEtykieta) {
            dc.setColor(koloSzary, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 0, Graphics.FONT_XTINY, mEtykieta,
                        Graphics.TEXT_JUSTIFY_CENTER);
            gora = maleH;
        }

        // stopka: cena i dzien, z ktorego pochodzi - tekst skracany do szerokosci
        var tekstStopki = stopkaDoSzerokosci(dc, w - 4);
        if (dol - gora - maleH >= minKwota) {
            var kolorStopki = koloSzary;
            if (!mZSieci) {
                kolorStopki = (tlo == Graphics.COLOR_BLACK)
                    ? Graphics.COLOR_YELLOW
                    : Graphics.COLOR_ORANGE;
            }
            dc.setColor(kolorStopki, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h - maleH, Graphics.FONT_XTINY, tekstStopki,
                        Graphics.TEXT_JUSTIFY_CENTER);
            dol = h - maleH;
        }

        // pasek postepu do celu oszczednosci na przejazd
        var udzial = 0.0;
        if (mCel > 0.0) {
            udzial = mZlote / mCel;
            if (udzial > 1.0) { udzial = 1.0; }
            if (udzial < 0.0) { udzial = 0.0; }
        }
        var celOsiagniety = (mCel > 0.0) && (mZlote >= mCel);
        if (mCel > 0.0 && (dol - gora - paskH - 6 >= minKwota) && (w > 40)) {
            var margines = 6;
            var bx = margines;
            var bw = w - 2 * margines;
            var by = dol - paskH - 3;
            var promien = paskH / 2;

            // tor paska
            dc.setColor(
                (tlo == Graphics.COLOR_BLACK) ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY,
                Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, bw, paskH, promien);

            // wypelnienie
            var wypelnienie = (bw * udzial).toNumber();
            if (wypelnienie > 0) {
                if (wypelnienie < paskH) { wypelnienie = paskH; }
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(bx, by, wypelnienie, paskH, promien);
            }
            dol = by - 3;
        }

        // glowna wartosc - na zielono, gdy cel przejazdu dowieziony
        var tekst = kwota(mZlote) + " " + mZl;
        var wolneH = dol - gora;
        var font = dobierzFont(dc, tekst, w - 4, wolneH);
        dc.setColor(celOsiagniety ? Graphics.COLOR_GREEN : kolor,
                    Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, gora + wolneH / 2, font, tekst,
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

    // Stopka w trzech dlugosciach - bierzemy najdluzsza, ktora miesci sie
    // w szerokosci kafla. Font XTINY jest najmniejszy jaki mamy, wiec jedyne,
    // co mozna skracac, to sam tekst.
    //   pelna:   "7,25 zl/l 09.08"
    //   srednia: "7,25 09.08"
    //   krotka:  "7,25"
    // Przy cenie awaryjnej sufiksem jest "?", ale i tak sygnalizuje ja kolor,
    // wiec w najkrotszym wariancie mozna go poswiecic.
    hidden function stopkaDoSzerokosci(dc as Graphics.Dc, maxW as Lang.Number) as Lang.String {
        var cenaTxt = kropkaNaPrzecinek(mCena.format("%.2f"));

        var sufiks = "?";
        if (mZSieci && mDataCeny != null && mDataCeny.length() >= 10) {
            sufiks = mDataCeny.substring(8, 10) + "." + mDataCeny.substring(5, 7);
        } else if (mBlad != null) {
            sufiks = mBlad;
        }

        var warianty = [
            cenaTxt + " " + mZlL + " " + sufiks,
            cenaTxt + " " + sufiks,
            cenaTxt
        ];
        for (var i = 0; i < warianty.size(); i++) {
            if (dc.getTextWidthInPixels(warianty[i], Graphics.FONT_XTINY) <= maxW) {
                return warianty[i];
            }
        }
        return cenaTxt;
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
