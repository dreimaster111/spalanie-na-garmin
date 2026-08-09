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
        var s = PriceStore.liczbaZUstawien("spalanie");
        if (s != null && s > 0.0 && s < 50.0) {
            mSpalanie = s;
        } else {
            mSpalanie = Config.DEFAULT_SPALANIE;
        }
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

        var zEtykieta = (h >= 52);
        var zeStopka = (h >= 52 + 2 * maleH);

        var gora = zEtykieta ? maleH : 0;
        var dol = zeStopka ? maleH : 0;

        // etykieta u gory
        if (zEtykieta) {
            dc.setColor(koloSzary, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 0, Graphics.FONT_XTINY, mEtykieta,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // glowna wartosc
        var tekst = kwota(mZlote) + " " + mZl;
        var wolneH = h - gora - dol;
        var font = dobierzFont(dc, tekst, w - 4, wolneH);
        dc.setColor(kolor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, gora + wolneH / 2, font, tekst,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // stopka: skad wzieta cena
        if (zeStopka) {
            var s = stopka();
            var kolorStopki = koloSzary;
            if (!mZSieci) {
                kolorStopki = (tlo == Graphics.COLOR_BLACK)
                    ? Graphics.COLOR_YELLOW
                    : Graphics.COLOR_ORANGE;
            }
            dc.setColor(kolorStopki, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h - maleH, Graphics.FONT_XTINY, s,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
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

    // np. "7,25 zl/l 09.08" albo "7,20 zl/l ?" gdy cena awaryjna
    hidden function stopka() as Lang.String {
        var s = kropkaNaPrzecinek(mCena.format("%.2f")) + " " + mZlL;
        if (mZSieci && mDataCeny != null && mDataCeny.length() >= 10) {
            s = s + " " + mDataCeny.substring(8, 10) + "." + mDataCeny.substring(5, 7);
        } else if (mBlad != null) {
            s = s + " " + mBlad;
        } else {
            s = s + " ?";
        }
        return s;
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
