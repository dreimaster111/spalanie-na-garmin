using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.WatchUi;

// Pelnoekranowy wykres slupkowy historii Pb95 z zaznaczeniem dnia.
// Gora/dol (albo przewijanie) przesuwa zaznaczenie, domyslnie na dzis.
class CenyView extends WatchUi.View {

    // -1 = zaznaczony ostatni (najnowszy) dzien
    var mWybor as Lang.Number = -1;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        CenyDane.przygotuj();
    }

    function przesun(oIle as Lang.Number) as Void {
        var n = CenyDane.ceny.size();
        if (n == 0) {
            return;
        }
        var i = (mWybor < 0) ? (n - 1) : mWybor;
        i = i + oIle;
        if (i < 0) { i = 0; }
        if (i > n - 1) { i = n - 1; }
        mWybor = i;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var maleH = dc.getFontHeight(Graphics.FONT_XTINY);

        var n = CenyDane.ceny.size();
        if (n == 0) {
            var info = (CenyDane.blad != null) ? CenyDane.blad : "Pobieram...";
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, "Ceny Pb95\n" + info,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var i = (mWybor < 0 || mWybor > n - 1) ? (n - 1) : mWybor;

        // naglowek: wybrany dzien + jego cena
        var data = CenyDane.daty[i];
        var dzien = data.substring(8, 10) + "." + data.substring(5, 7);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 9, Graphics.FONT_XTINY, "Pb95  ·  " + dzien,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 9 + maleH, Graphics.FONT_NUMBER_MEDIUM,
                    naPrzecinek(CenyDane.ceny[i].format("%.2f")),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // zakres min/max calej historii
        var min = CenyDane.ceny[0];
        var max = CenyDane.ceny[0];
        for (var k = 1; k < n; k++) {
            if (CenyDane.ceny[k] < min) { min = CenyDane.ceny[k]; }
            if (CenyDane.ceny[k] > max) { max = CenyDane.ceny[k]; }
        }
        var zakres = max - min;
        if (zakres < 0.01) { zakres = 0.01; }

        // wykres: pas na dole, szerokosc ~72% ekranu (bezpieczna na kole)
        var wykresSzer = w * 72 / 100;
        var x0 = cx - wykresSzer / 2;
        var dolW = h * 78 / 100;
        var wysW = h * 30 / 100;
        var krok = wykresSzer.toFloat() / n;
        var slupek = (krok - 1.0).toNumber();
        if (slupek < 2) { slupek = 2; }

        for (var k = 0; k < n; k++) {
            var sh = 3 + ((CenyDane.ceny[k] - min) / zakres * (wysW - 3)).toNumber();
            dc.setColor((k == i) ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle((x0 + k * krok).toNumber(), dolW - sh, slupek, sh);
        }

        // zakres pod wykresem, wysrodkowany - boczne etykiety obcinala tarcza
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dolW + 6, Graphics.FONT_XTINY,
                    "min " + naPrzecinek(min.format("%.2f"))
                    + "   max " + naPrzecinek(max.format("%.2f")),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function naPrzecinek(s as Lang.String) as Lang.String {
        var i = s.find(".");
        if (i == null) {
            return s;
        }
        return s.substring(0, i) + "," + s.substring(i + 1, s.length());
    }
}
