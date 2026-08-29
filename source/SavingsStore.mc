using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Licznik laczny: ile zlotych zaoszczedzily WSZYSTKIE przejazdy w tym roku.
//
// Pole danych nie dostaje zadnego sygnalu "trening zapisany", wiec sumy nie
// da sie doliczyc na koncu jazdy. Zamiast tego dopisujemy PRZYROSTY w trakcie:
// co pol minuty compute() podaje oszczednosc od poczatku biezacego treningu,
// a my dokladamy do sumy roznice wzgledem poprzedniego wywolania. Poczatek
// nowego treningu poznajemy po tym, ze wartosc SPADLA (dystans liczy sie
// od zera) - wtedy punkt odniesienia tez wraca do zera.
//
// Modul nie jest (:background) - usluga w tle go nie potrzebuje, a jej pula
// pamieci (32 kB) jest zbyt cenna.
module SavingsStore {

    const KEY_RAZEM = "razemZl";    // Float - suma [zl] w biezacym roku
    const KEY_ROK   = "razemRok";   // Number - rok, ktorego dotyczy suma
    const KEY_SESJA = "razemSesja"; // Float - ile z biezacego treningu juz doliczono

    function razem() as Lang.Float {
        return odczytaj(KEY_RAZEM, 0.0);
    }

    // zl = oszczednosc od poczatku biezacego treningu (rosnie z dystansem).
    // Wolac co ~30 s - kazde wywolanie z nowym groszem to zapis do flasha.
    function aktualizuj(zl as Lang.Float) as Void {
        var rok = Gregorian.info(Time.now(), Time.FORMAT_SHORT).year;
        var suma = odczytaj(KEY_RAZEM, 0.0);
        var sesja = odczytaj(KEY_SESJA, 0.0);

        if (rok != odczytajRok()) {
            // nowy rok - licznik startuje od zera
            suma = 0.0;
            sesja = 0.0;
        }
        if (zl < sesja - 0.01) {
            // wartosc spadla = nowy trening; dotychczasowa sesja juz jest w sumie
            sesja = 0.0;
        }

        var przyrost = zl - sesja;
        if (przyrost < 0.01) {
            return;     // nic nowego - nie zuzywamy flasha
        }
        try {
            Storage.setValue(KEY_RAZEM, suma + przyrost);
            Storage.setValue(KEY_SESJA, zl);
            Storage.setValue(KEY_ROK, rok);
        } catch (e) {
        }
    }

    // (w module nie ma "hidden" - pomocnicza, nie wolaj jej z zewnatrz)
    function odczytaj(klucz as Lang.String, awaryjnie as Lang.Float) as Lang.Float {
        try {
            var v = Storage.getValue(klucz);
            if (v instanceof Lang.Float || v instanceof Lang.Number || v instanceof Lang.Double) {
                return v.toFloat();
            }
        } catch (e) {
        }
        return awaryjnie;
    }

    function odczytajRok() as Lang.Number {
        try {
            var v = Storage.getValue(KEY_ROK);
            if (v instanceof Lang.Number) {
                return v;
            }
        } catch (e) {
        }
        return 0;
    }
}
