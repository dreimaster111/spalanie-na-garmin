using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// Dane widgetu: pobieranie pliku "YYYY-MM-DD,cena" (30 linii) i cache
// w Storage, zeby po otwarciu bez telefonu tez bylo co pokazac.
module CenyDane {

    const URL = "https://raw.githubusercontent.com/dreimaster111/spalanie-na-garmin/main/data/pb95-widget.txt";
    const KEY_TEKST = "widgetTekst";     // surowy pobrany plik
    const KEY_POBRANO = "widgetPobrano"; // epoch ostatniego pobrania
    const KEY_GLANCE = "glanceDane";     // [data, cena, poprzednia] dla podgladu
    const ODSWIEZ_CO_SEK = 6 * 3600;

    var daty as Lang.Array<Lang.String> = [] as Lang.Array<Lang.String>;
    var ceny as Lang.Array<Lang.Float> = [] as Lang.Array<Lang.Float>;
    var blad as Lang.String or Null = null;
    var wToku as Lang.Boolean = false;

    // Wczytuje cache i - jesli danych brak albo sa stare - rusza do sieci.
    function przygotuj() as Void {
        if (daty.size() == 0) {
            var t = null;
            try {
                t = Storage.getValue(KEY_TEKST);
            } catch (e) {
            }
            if (t instanceof Lang.String) {
                parsuj(t);
                zapiszGlance();     // starsza wersja widgetu nie zapisywala podsumowania
            }
        }
        var ostatnio = null;
        try {
            ostatnio = Storage.getValue(KEY_POBRANO);
        } catch (e) {
        }
        var stare = (ostatnio == null) || !(ostatnio instanceof Lang.Number)
            || (Time.now().value() - ostatnio >= ODSWIEZ_CO_SEK);
        if (stare || daty.size() == 0) {
            pobierz();
        }
    }

    function pobierz() as Void {
        if (wToku) {
            return;
        }
        try {
            if (!System.getDeviceSettings().phoneConnected) {
                blad = "brak telefonu";
                return;
            }
            wToku = true;
            Communications.makeWebRequest(URL, null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            }, new Lang.Method(CenyDane, :onOdpowiedz));
        } catch (e) {
            wToku = false;
            blad = "blad sieci";
        }
    }

    function onOdpowiedz(kod as Lang.Number,
                         dane as Lang.Dictionary or Lang.String or Null) as Void {
        wToku = false;
        if (kod == 200 && dane instanceof Lang.String) {
            parsuj(dane);
            if (daty.size() > 0) {
                blad = null;
                try {
                    Storage.setValue(KEY_TEKST, dane);
                    Storage.setValue(KEY_POBRANO, Time.now().value());
                } catch (e) {
                }
                zapiszGlance();
            } else {
                blad = "zly format";
            }
        } else {
            blad = "HTTP " + kod;
        }
        WatchUi.requestUpdate();
    }

    // Krotkie podsumowanie dla podgladu (glance): ostatnia data, cena
    // i poprzednia INNA cena do strzalki trendu. Glance ma malo pamieci
    // i nie parsuje calego roku - czyta tylko te trzy wartosci.
    function zapiszGlance() as Void {
        var n = ceny.size();
        if (n == 0) {
            return;
        }
        var poprzednia = -1.0;
        for (var i = n - 2; i >= 0; i--) {
            if ((ceny[i] - ceny[n - 1]).abs() >= 0.005) {
                poprzednia = ceny[i];
                break;
            }
        }
        try {
            Storage.setValue(KEY_GLANCE, [daty[n - 1], ceny[n - 1], poprzednia]);
        } catch (e) {
        }
    }

    function parsuj(tekst as Lang.String) as Void {
        var d = [] as Lang.Array<Lang.String>;
        var c = [] as Lang.Array<Lang.Float>;
        var reszta = tekst;
        while (reszta.length() > 0 && d.size() < 400) {
            var nl = reszta.find("\n");
            var linia;
            if (nl != null) {
                linia = reszta.substring(0, nl);
                reszta = reszta.substring(nl + 1, reszta.length());
            } else {
                linia = reszta;
                reszta = "";
            }
            if (linia.length() >= 12 && linia.substring(4, 5).equals("-")) {
                var cena = linia.substring(11, linia.length()).toFloat();
                if (cena != null && cena > 0.0 && cena < 100.0) {
                    d.add(linia.substring(0, 10));
                    c.add(cena);
                }
            }
        }
        if (d.size() > 0) {
            daty = d;
            ceny = c;
        }
    }
}
