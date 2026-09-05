using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.WatchUi;

// Podglad (glance) na liscie podgladow: dzisiejsza cena Pb95 ze strzalka
// trendu i data, bez wchodzenia do widgetu.
//
// Glance dziala w osobnej, bardzo malej puli pamieci i nie ma dostepu do
// sieci, wiec NIE korzysta z CenyDane (caly rok cen + makeWebRequest).
// Czyta tylko trzy wartosci, ktore widget zapisal w Storage po pobraniu.
(:glance)
class CenyGlance extends WatchUi.GlanceView {

    hidden var mData as Lang.String or Null = null;
    hidden var mCena as Lang.Float or Null = null;
    hidden var mPoprzednia as Lang.Float or Null = null;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() as Void {
        mData = null;
        mCena = null;
        mPoprzednia = null;
        try {
            var v = Storage.getValue("glanceDane");
            if (v instanceof Lang.Array && v.size() >= 3) {
                if (v[0] instanceof Lang.String) { mData = v[0]; }
                if (v[1] instanceof Lang.Float) { mCena = v[1]; }
                if (v[2] instanceof Lang.Float && v[2] > 0.0) { mPoprzednia = v[2]; }
            }
            if (mCena == null) {
                // brak podsumowania (np. widget zaktualizowany, ale jeszcze nie
                // otwarty) - wyciagnij je z ogona pobranego pliku w cache
                var t = Storage.getValue("widgetTekst");
                if (t instanceof Lang.String) {
                    zOgona(t);
                }
            }
        } catch (e) {
        }
    }

    // Czyta OSTATNIE linie "YYYY-MM-DD,cena" skanujac tekst od konca -
    // bez parsowania calego roku, na ktory glance nie ma pamieci ani czasu.
    // Ostatnia linia = dzisiejsza cena; cofa sie dalej (max ~20 linii)
    // po pierwsza INNA cene do strzalki trendu.
    hidden function zOgona(t as Lang.String) as Void {
        var koniec = t.length();
        while (koniec > 0 && t.substring(koniec - 1, koniec).equals("\n")) {
            koniec--;
        }
        var linie = 0;
        var k = koniec;
        while (k > 0 && linie < 20) {
            // poczatek biezacej linii
            var start = k;
            while (start > 0 && !t.substring(start - 1, start).equals("\n")) {
                start--;
            }
            var linia = t.substring(start, k);
            if (linia.length() >= 12 && linia.substring(4, 5).equals("-")) {
                var c = linia.substring(11, linia.length()).toFloat();
                if (c != null && c > 0.0) {
                    if (mCena == null) {
                        mCena = c;
                        mData = linia.substring(0, 10);
                    } else if ((c - mCena).abs() >= 0.005) {
                        mPoprzednia = c;
                        return;
                    }
                }
            }
            linie++;
            k = start - 1;      // przeskocz znak nowej linii
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var fontT = Graphics.FONT_GLANCE;
        var fontC = (h >= 60) ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
        var hT = dc.getFontHeight(fontT);
        var hC = dc.getFontHeight(fontC);
        // dwa wiersze wysrodkowane w pionie w pasie podgladu
        var y0 = (h - hT - hC) / 2;
        if (y0 < 0) { y0 = 0; }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, y0, fontT, "CENA PB95", Graphics.TEXT_JUSTIFY_LEFT);

        if (mCena == null) {
            // placeholder malym fontem - w pasie podgladu nie ma miejsca na wiecej
            dc.drawText(0, y0 + hT, fontT, "otworz, aby pobrac", Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }

        // cena fontem TEKSTOWYM (ma przecinek - fonty cyfrowe fenixa 6 nie)
        var cenaTxt = naPrzecinek(mCena.format("%.2f")) + " zl";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, y0 + hT, fontC, cenaTxt, Graphics.TEXT_JUSTIFY_LEFT);
        var x = dc.getTextWidthInPixels(cenaTxt, fontC) + 6;

        // strzalka trendu: czerwona w gore = drozej, zielona w dol = taniej
        if (mPoprzednia != null) {
            var cy = y0 + hT + hC / 2;
            var s = hC / 5;
            if (s < 4) { s = 4; }
            if (mCena > mPoprzednia + 0.001) {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon([[x, cy + s / 2], [x + 2 * s, cy + s / 2], [x + s, cy - s]]
                    as Lang.Array<[Lang.Numeric, Lang.Numeric]>);
                x = x + 2 * s + 6;
            } else if (mCena < mPoprzednia - 0.001) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon([[x, cy - s / 2], [x + 2 * s, cy - s / 2], [x + s, cy + s]]
                    as Lang.Array<[Lang.Numeric, Lang.Numeric]>);
                x = x + 2 * s + 6;
            }
        }

        // data notowania, o ile sie jeszcze miesci
        if (mData != null && mData.length() >= 10) {
            var dataTxt = mData.substring(8, 10) + "." + mData.substring(5, 7);
            if (x + dc.getTextWidthInPixels(dataTxt, fontT) <= w) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y0 + hT + (hC - hT) / 2, fontT, dataTxt,
                            Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }

    hidden function naPrzecinek(s as Lang.String) as Lang.String {
        var i = s.find(".");
        if (i == null) {
            return s;
        }
        return s.substring(0, i) + "," + s.substring(i + 1, s.length());
    }
}
