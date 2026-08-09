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
