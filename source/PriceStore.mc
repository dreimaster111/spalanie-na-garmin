using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Time;

// Wspolny "magazyn" ceny paliwa. Storage jest widoczny i dla procesu glownego
// (pole danych na ekranie), i dla uslugi w tle - dlatego usluga po prostu
// zapisuje tu cene, a pole danych ja sobie odczytuje. Nie trzeba zadnej
// komunikacji miedzy procesami.
(:background)
module PriceStore {

    const KEY_CENA = "cena";        // Float, zl/l
    const KEY_DATA = "cenaData";    // String "YYYY-MM-DD" - z ktorego dnia cena
    const KEY_POBRANO = "cenaPobrano"; // Number, czas pobrania (epoch)
    const KEY_BLAD = "cenaBlad";    // String albo null
    const KEY_SPALANIE = "ustSpalanie"; // Float, l/100 km z pobranego pliku
    const KEY_CEL = "ustCel";       // Float, cel na przejazd [zl] z pobranego pliku
    const KEY_POPRZEDNIA = "cenaPoprzednia"; // Float, ostatnia INNA cena - do strzalki trendu
    const KEY_HISTORIA = "cenaHistoria"; // Array<Float>, ostatnie ~14 cen - do mini-wykresu

    // Cena do liczenia oszczednosci: pobrana z sieci, a jak jej nie ma -
    // awaryjna z ustawien / z Config.
    function cena() as Lang.Float {
        var v = null;
        try {
            v = Storage.getValue(KEY_CENA);
        } catch (e) {
            v = null;
        }
        if (v != null && v instanceof Lang.Float && v > 0.0) {
            return v;
        }
        return cenaAwaryjna();
    }

    function cenaAwaryjna() as Lang.Float {
        var v = liczbaZUstawien("cenaAwaryjna");
        if (v != null && v > 0.0) {
            return v;
        }
        return Config.DEFAULT_CENA;
    }

    // Spalanie auta [l/100 km]. Kolejnosc wazna:
    //  1) linia "spalanie=" z pobranego pliku - to jedyna droga, zeby zmienic
    //     wartosc w apce wgranej recznie (sideload nie widzi ustawien z telefonu),
    //  2) ustawienie z telefonu / properties.xml,
    //  3) wartosc z Config.mc.
    function spalanie() as Lang.Float {
        var v = liczbaZeStorage(KEY_SPALANIE);
        if (v != null && v > 0.0 && v < 50.0) {
            return v;
        }
        var p = liczbaZUstawien("spalanie");
        if (p != null && p > 0.0 && p < 50.0) {
            return p;
        }
        return Config.DEFAULT_SPALANIE;
    }

    // Cel oszczednosci na przejazd [zl]; 0 = pasek postepu sie nie rysuje.
    function cel() as Lang.Float {
        var v = liczbaZeStorage(KEY_CEL);
        if (v != null && v >= 0.0) {
            return v;
        }
        var p = liczbaZUstawien("celZl");
        if (p != null && p >= 0.0) {
            return p;
        }
        return Config.DEFAULT_CEL;
    }

    // (w module nie ma "hidden" - to pomocnicza, nie wolaj jej z zewnatrz)
    function liczbaZeStorage(klucz as Lang.String) as Lang.Float or Null {
        try {
            var v = Storage.getValue(klucz);
            if (v instanceof Lang.Float || v instanceof Lang.Number || v instanceof Lang.Double) {
                return v.toFloat();
            }
        } catch (e) {
        }
        return null;
    }

    // Kierunek ostatniej zmiany ceny: 1 = podrozala, -1 = staniala,
    // 0 = brak danych (albo cena awaryjna, ktora nie ma z czym sie rownac).
    function trend() as Lang.Number {
        if (!zSieci()) {
            return 0;
        }
        var pop = liczbaZeStorage(KEY_POPRZEDNIA);
        if (pop == null || pop <= 0.0) {
            return 0;
        }
        var c = cena();
        if (c > pop + 0.001) {
            return 1;
        }
        if (c < pop - 0.001) {
            return -1;
        }
        return 0;
    }

    // Historia cen do mini-wykresu; pusta tablica, gdy nic nie przyszlo.
    function historia() as Lang.Array<Lang.Float> {
        try {
            var v = Storage.getValue(KEY_HISTORIA);
            if (v instanceof Lang.Array && v.size() >= 2) {
                return v as Lang.Array<Lang.Float>;
            }
        } catch (e) {
        }
        return [] as Lang.Array<Lang.Float>;
    }

    function dataCeny() as Lang.String or Null {
        try {
            var d = Storage.getValue(KEY_DATA);
            if (d instanceof Lang.String) {
                return d;
            }
        } catch (e) {
        }
        return null;
    }

    // true = cena pochodzi z internetu (a nie z wartosci awaryjnej)
    function zSieci() as Lang.Boolean {
        try {
            var v = Storage.getValue(KEY_CENA);
            return (v != null && v instanceof Lang.Float && v > 0.0);
        } catch (e) {
        }
        return false;
    }

    function blad() as Lang.String or Null {
        try {
            var b = Storage.getValue(KEY_BLAD);
            if (b instanceof Lang.String) {
                return b;
            }
        } catch (e) {
        }
        return null;
    }

    // Czy warto sie fatygowac po nowa cene
    function trzebaOdswiezyc() as Lang.Boolean {
        var last = null;
        try {
            last = Storage.getValue(KEY_POBRANO);
        } catch (e) {
            last = null;
        }
        if (last == null || !(last instanceof Lang.Number)) {
            return true;
        }
        return (Time.now().value() - last) >= Config.ODSWIEZ_CO_SEK;
    }

    // --- pomocnicze: czytanie ustawien z telefonu ------------------------
    function tekstZUstawien(klucz as Lang.String, awaryjnie as Lang.String) as Lang.String {
        var v = null;
        try {
            v = Properties.getValue(klucz);
        } catch (e) {
            v = null;
        }
        if (v instanceof Lang.String && v.length() > 0) {
            return v;
        }
        return awaryjnie;
    }

    function liczbaZUstawien(klucz as Lang.String) as Lang.Float or Null {
        var v = null;
        try {
            v = Properties.getValue(klucz);
        } catch (e) {
            v = null;
        }
        if (v == null) {
            return null;
        }
        if (v instanceof Lang.Float || v instanceof Lang.Number || v instanceof Lang.Double) {
            return v.toFloat();
        }
        if (v instanceof Lang.String) {
            return v.toFloat();
        }
        return null;
    }
}
