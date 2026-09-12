using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

// Historia cen Pb95 od poczatku roku.
//
// Ekran pokazuje OKNO 7 dni jako szerokie slupki (czytelne z roweru,
// nie 150 wlosow jak przy calym roku naraz). Gora/dol przesuwa zaznaczony
// dzien; gdy zaznaczenie dojdzie do krawedzi okna, okno plynie dalej -
// tak da sie dojechac od dzis do 1 stycznia. Naglowek zawsze opisuje
// zaznaczony dzien: dzien tygodnia, data, duza cena i zmiana wzgledem
// poprzedniego notowania.
class CenyView extends WatchUi.View {

    const OKNO = 7;                          // ile slupkow widac naraz

    var mWybor as Lang.Number = -1;          // -1 = najnowszy dzien
    hidden var mOkno as Lang.Number = -1;    // indeks pierwszego slupka okna

    hidden const DNI = ["nd", "pn", "wt", "sr", "cz", "pt", "sb"];
    hidden const MIES = ["sty", "lut", "mar", "kwi", "maj", "cze",
                         "lip", "sie", "wrz", "paz", "lis", "gru"];

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
        var i = (mWybor < 0 || mWybor > n - 1) ? (n - 1) : mWybor;
        i = i + oIle;
        if (i < 0) { i = 0; }
        if (i > n - 1) { i = n - 1; }
        // najnowszy dzien trzymamy jako sentinel -1: po odswiezeniu, ktore
        // dolozy dzisiejsza cene, zaznaczenie samo na nia przeskoczy
        mWybor = (i == n - 1) ? -1 : i;
        WatchUi.requestUpdate();
    }

    function doDzis() as Void {
        mWybor = -1;
        mOkno = -1;
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
            rysujSplash(dc, cx, h);
            return;
        }

        var i = (mWybor < 0 || mWybor > n - 1) ? (n - 1) : mWybor;

        // okno podaza za zaznaczeniem
        if (mOkno < 0) { mOkno = n - OKNO; }
        if (mOkno < 0) { mOkno = 0; }
        if (i < mOkno) { mOkno = i; }
        if (i > mOkno + OKNO - 1) { mOkno = i - OKNO + 1; }
        if (mOkno + OKNO > n) { mOkno = n - OKNO; }
        if (mOkno < 0) { mOkno = 0; }

        // --- naglowek: dzien, cena, zmiana ---------------------------------
        // Bez tytulu "Cena Pb95" - uzytkownik wie, co otworzyl, a kazdy
        // wiersz u gory tarczy to wiersz mniej na dole, gdzie jest ciasno.
        var data = CenyDane.daty[i];
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 4 / 100, Graphics.FONT_SMALL,
                    dzienTygodnia(data) + ", " + data.substring(8, 10) + "."
                        + data.substring(5, 7) + (CenyDane.wToku ? " ..." : ""),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Duza cena skladana z dwoch czesci: zlotowki fontem CYFROWYM,
        // ",gr" mniejszym fontem tekstowym. Fonty FONT_NUMBER_* na fenixie 6
        // NIE MAJA glifu przecinka (maja tylko cyfry i kropke), wiec przecinek
        // musi przyjsc z fontu tekstowego - tak samo robi to pole danych.
        var cenaTxt = CenyDane.ceny[i].format("%.2f");
        var kropka = cenaTxt.find(".");
        var duzy = (kropka == null) ? cenaTxt : cenaTxt.substring(0, kropka);
        var maly = (kropka == null) ? ""
            : "," + cenaTxt.substring(kropka + 1, cenaTxt.length());
        var fontCeny = Graphics.FONT_NUMBER_MEDIUM;
        var fontGr = Graphics.FONT_SMALL;
        var yCeny = h * 14 / 100;
        var hd = dc.getFontHeight(fontCeny);
        var wd = dc.getTextWidthInPixels(duzy, fontCeny);
        var wm = dc.getTextWidthInPixels(maly, fontGr);
        var xCeny = cx - (wd + wm) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(xCeny, yCeny, fontCeny, duzy, Graphics.TEXT_JUSTIFY_LEFT);
        // korekta jak w polu danych: fonty cyfrowe maja pod cyframi pusty pas
        dc.drawText(xCeny + wd, yCeny + hd - dc.getFontHeight(fontGr) - hd / 6,
                    fontGr, maly, Graphics.TEXT_JUSTIFY_LEFT);

        // zmiana wzgledem poprzedniego notowania, obok ceny; gdy poprzednie
        // notowanie nie jest z dnia poprzedniego (dziura w danych), rysujemy
        // na szaro - to nie jest zmiana "z dnia na dzien"
        if (i > 0) {
            var delta = CenyDane.ceny[i] - CenyDane.ceny[i - 1];
            var ciagle = kolejnyDzien(CenyDane.daty[i - 1], CenyDane.daty[i]);
            var deltaTxt;
            var kolorD;
            if (delta > 0.004) {
                deltaTxt = "+" + naPrzecinek(delta.format("%.2f"));
                kolorD = ciagle ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY;
            } else if (delta < -0.004) {
                deltaTxt = naPrzecinek(delta.format("%.2f"));
                kolorD = ciagle ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY;
            } else {
                deltaTxt = "=";
                kolorD = Graphics.COLOR_LT_GRAY;
            }
            dc.setColor(kolorD, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xCeny + wd + wm + 6,
                        yCeny + hd / 2 - maleH / 2,
                        Graphics.FONT_XTINY, deltaTxt, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // --- zmiana tygodniowa i miesieczna, pod cena ------------------------
        // Jednodniowy skok obok ceny malo mowi; tu porownanie z notowaniem
        // sprzed 7 i 30 dni (najblizszym NIE nowszym niz ta data - w danych
        // bywaja dziury). Kazda wartosc w kolorze kierunku.
        // hd fontu cyfrowego zawiera duzy pusty pas pod cyframi (ok. 1/6),
        // wiec wiersz siada tuz pod widocznymi cyframi, nie pod calym fontem
        rysujZmiany(dc, cx, yCeny + hd - hd / 6 + 2, i, maleH);

        // --- wykres: 7 szerokich slupkow -----------------------------------
        var goraW = h * 52 / 100;
        var dolW = h * 71 / 100;
        var wysW = dolW - goraW;
        var chartW = w * 66 / 100;
        var pokaz = (n < OKNO) ? n : OKNO;
        var krok = chartW / OKNO;
        var x0 = cx - (krok * pokaz) / 2;

        // skala z widocznego okna - grosze robia roznice, wiec nie od zera
        var visMin = CenyDane.ceny[mOkno];
        var visMax = visMin;
        for (var k = mOkno; k < mOkno + pokaz; k++) {
            if (CenyDane.ceny[k] < visMin) { visMin = CenyDane.ceny[k]; }
            if (CenyDane.ceny[k] > visMax) { visMax = CenyDane.ceny[k]; }
        }
        var zakres = visMax - visMin;
        if (zakres < 0.01) { zakres = 0.01; }

        for (var k = 0; k < pokaz; k++) {
            var idx = mOkno + k;
            var v = CenyDane.ceny[idx];
            var sh = 5 + ((v - visMin) / zakres * (wysW - 5)).toNumber();
            var bx = (x0 + k * krok).toNumber() + 2;
            var bw = krok - 4;
            dc.setColor((idx == i) ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, dolW - sh, bw, sh, 3);

            // dzien miesiaca pod slupkiem
            var dzien = CenyDane.daty[idx].substring(8, 10);
            if (dzien.substring(0, 1).equals("0")) {
                dzien = dzien.substring(1, 2);
            }
            dc.setColor((idx == i) ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(bx + bw / 2, dolW + 3, Graphics.FONT_XTINY, dzien,
                        Graphics.TEXT_JUSTIFY_CENTER);
            // pierwszy dzien miesiaca dostaje pod numerem skrot miesiaca -
            // przy przelomie (30 31 1 2 3) od razu widac, ktory to miesiac
            if (dzien.equals("1")) {
                var m = CenyDane.daty[idx].substring(5, 7).toNumber();
                if (m != null && m >= 1 && m <= 12) {
                    dc.drawText(bx + bw / 2, dolW + 1 + maleH, Graphics.FONT_XTINY,
                                MIES[m - 1], Graphics.TEXT_JUSTIFY_CENTER);
                }
            }
        }

        // strzalki: czy jest cos starszego / nowszego poza oknem
        var ySt = goraW + wysW / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (mOkno > 0) {
            // grot w LEWO - tam jest starsza historia
            dc.fillPolygon([[x0.toNumber() - 16, ySt],
                            [x0.toNumber() - 8, ySt - 6],
                            [x0.toNumber() - 8, ySt + 6]] as Lang.Array<[Lang.Numeric, Lang.Numeric]>);
        }
        if (mOkno + pokaz < n) {
            // grot w PRAWO - nowsze dni
            var xp = (x0 + pokaz * krok).toNumber();
            dc.fillPolygon([[xp + 16, ySt],
                            [xp + 8, ySt - 6],
                            [xp + 8, ySt + 6]] as Lang.Array<[Lang.Numeric, Lang.Numeric]>);
        }

        // --- stopka: zakres calej wczytanej historii -----------------------
        var min = CenyDane.ceny[0];
        var max = min;
        for (var k = 1; k < n; k++) {
            if (CenyDane.ceny[k] < min) { min = CenyDane.ceny[k]; }
            if (CenyDane.ceny[k] > max) { max = CenyDane.ceny[k]; }
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dolW + 2 * maleH + 4, Graphics.FONT_XTINY,
                    "rok:  " + naPrzecinek(min.format("%.2f")) + " - "
                        + naPrzecinek(max.format("%.2f")),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    hidden function rysujSplash(dc as Graphics.Dc, cx as Lang.Number,
                                h as Lang.Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 30 / 100, Graphics.FONT_MEDIUM, "Ceny Pb95",
                    Graphics.TEXT_JUSTIFY_CENTER);
        var info = CenyDane.wToku ? "Pobieram..."
            : ((CenyDane.blad != null) ? CenyDane.blad : "Brak danych");
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 45 / 100, Graphics.FONT_SMALL, info,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 60 / 100, Graphics.FONT_XTINY, "START = odswiez",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // "tydz. +0,32  ·  mies. -0,10" wysrodkowane; wartosci kolorowane.
    hidden function rysujZmiany(dc as Graphics.Dc, cx as Lang.Number,
                                y as Lang.Number, i as Lang.Number,
                                maleH as Lang.Number) as Void {
        var f = Graphics.FONT_XTINY;
        var czesci = [
            ["tydz. ", Graphics.COLOR_LT_GRAY],
            [tekstZmiany(zmianaOd(i, 7)), kolorZmiany(zmianaOd(i, 7))],
            ["   mies. ", Graphics.COLOR_LT_GRAY],
            [tekstZmiany(zmianaOd(i, 30)), kolorZmiany(zmianaOd(i, 30))]
        ];
        var szer = 0;
        for (var k = 0; k < czesci.size(); k++) {
            szer += dc.getTextWidthInPixels(czesci[k][0] as Lang.String, f);
        }
        var x = cx - szer / 2;
        for (var k = 0; k < czesci.size(); k++) {
            var t = czesci[k][0] as Lang.String;
            dc.setColor(czesci[k][1], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, t, Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(t, f);
        }
    }

    hidden function tekstZmiany(d as Lang.Float or Null) as Lang.String {
        if (d == null) {
            return "-";
        }
        if (d > 0.004) {
            return "+" + naPrzecinek(d.format("%.2f"));
        }
        if (d < -0.004) {
            return naPrzecinek(d.format("%.2f"));
        }
        return "0,00";
    }

    hidden function kolorZmiany(d as Lang.Float or Null) {
        if (d == null) {
            return Graphics.COLOR_LT_GRAY;
        }
        if (d > 0.004) {
            return Graphics.COLOR_RED;
        }
        if (d < -0.004) {
            return Graphics.COLOR_GREEN;
        }
        return Graphics.COLOR_LT_GRAY;
    }

    // Roznica ceny[i] wzgledem ostatniego notowania sprzed >= `dni` dni.
    // null, gdy historia nie siega tak daleko.
    hidden function zmianaOd(i as Lang.Number, dni as Lang.Number) as Lang.Float or Null {
        var mi = moment(CenyDane.daty[i]);
        if (mi == null) {
            return null;
        }
        var cel = mi.value() - dni * 86400;
        for (var k = i - 1; k >= 0; k--) {
            var mk = moment(CenyDane.daty[k]);
            if (mk != null && mk.value() <= cel) {
                return CenyDane.ceny[i] - CenyDane.ceny[k];
            }
        }
        return null;
    }

    hidden function moment(data as Lang.String) as Time.Moment or Null {
        try {
            return Gregorian.moment({
                :year => data.substring(0, 4).toNumber(),
                :month => data.substring(5, 7).toNumber(),
                :day => data.substring(8, 10).toNumber(),
                :hour => 12
            });
        } catch (e) {
            return null;
        }
    }

    // Czy data b jest dokladnie nastepnym dniem po a? (obie "YYYY-MM-DD")
    hidden function kolejnyDzien(a as Lang.String, b as Lang.String) as Lang.Boolean {
        try {
            var ma = Gregorian.moment({
                :year => a.substring(0, 4).toNumber(),
                :month => a.substring(5, 7).toNumber(),
                :day => a.substring(8, 10).toNumber(),
                :hour => 12
            });
            var mb = Gregorian.moment({
                :year => b.substring(0, 4).toNumber(),
                :month => b.substring(5, 7).toNumber(),
                :day => b.substring(8, 10).toNumber(),
                :hour => 12
            });
            var roznica = mb.value() - ma.value();
            return roznica > 20 * 3600 && roznica < 28 * 3600;
        } catch (e) {
            return true;    // w razie watpliwosci nie strasz szaroscia
        }
    }

    // "2026-08-29" -> "pt" (skrot dnia tygodnia)
    hidden function dzienTygodnia(data as Lang.String) as Lang.String {
        try {
            var m = Gregorian.moment({
                :year => data.substring(0, 4).toNumber(),
                :month => data.substring(5, 7).toNumber(),
                :day => data.substring(8, 10).toNumber(),
                :hour => 12
            });
            var dow = Gregorian.info(m, Time.FORMAT_SHORT).day_of_week as Lang.Number;
            return DNI[dow - 1];
        } catch (e) {
            return "";
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
