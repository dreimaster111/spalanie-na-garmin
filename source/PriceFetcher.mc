using Toybox.Communications;
using Toybox.Background;
using Toybox.Application.Storage;
using Toybox.StringUtil;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

// Pobiera z internetu srednia cene benzyny 95 na dany dzien.
//
// Zegarek NIE potrafi taniej sparsowac strony WWW (kazdy serwis z cenami to
// ~100 kB HTML-a, a usluga w tle ma 32 kB pamieci), dlatego posrednikiem jest
// maly plik tekstowy w repo GitHub, aktualizowany raz dziennie przez
// GitHub Actions (tools/fetch_pb95.py). Format pliku - jedna linia:
//
//     2026-08-09,7.25
//
// Obslugiwane sa dwa adresy:
//  1) raw.githubusercontent.com/... (repo publiczne) - zwykly tekst,
//  2) api.github.com/repos/.../contents/... (repo prywatne) - JSON z polem
//     "content" zakodowanym base64; wymaga tokenu PAT.
//
// Klasa NIE dotyka WatchUi - dziala tak samo w tle jak i na pierwszym planie.
// Wynik laduje w Storage, a pole danych odczytuje go przy kolejnym compute().
(:background)
class PriceFetcher {

    hidden var mZajety as Lang.Boolean = false;
    hidden var mWTle as Lang.Boolean = false;

    // Ustawiane, gdy urzadzenie w ogole nie pozwala tej instancji siegac do
    // sieci - wtedy przestajemy probowac. Dotyczy pola danych na pierwszym
    // planie na CIQ < 7.0: bezposredni dostep do Communications dostaly pola
    // danych dopiero w System 7 (SDK 7.0.0), a fenix 6X ma CIQ 3.4.5.
    // Na starszych zegarkach cene przynosi wylacznie usluga w tle.
    hidden var mBezSieci as Lang.Boolean = false;

    // wTle = true, gdy pobieranie odpala usluga w tle (musi zakonczyc sie
    // wywolaniem Background.exit, inaczej system ubije ja po 30 s)
    function initialize(wTle as Lang.Boolean) {
        mWTle = wTle;
    }

    function zajety() as Lang.Boolean {
        return mZajety;
    }

    // Pobierz tylko jesli cena jest stara. Zwraca true, gdy zapytanie poszlo.
    function pobierzJesliStara() as Lang.Boolean {
        if (!PriceStore.trzebaOdswiezyc()) {
            return false;
        }
        return pobierz();
    }

    function pobierz() as Lang.Boolean {
        if (mZajety || mBezSieci) {
            return false;
        }
        // bez telefonu w zasiegu nie ma sensu probowac
        try {
            if (!System.getDeviceSettings().phoneConnected) {
                zapiszBlad("brak telefonu");
                return false;
            }
        } catch (e) {
        }

        var url = PriceStore.tekstZUstawien("adresCeny", Config.DEFAULT_URL);
        if (url.length() < 8) {
            url = Config.DEFAULT_URL;
        }
        var github = (url.find("api.github.com") != null);

        var naglowki = {};
        var token = PriceStore.tekstZUstawien("token", Config.DEFAULT_TOKEN);
        if (github && token.length() > 10) {
            naglowki["Authorization"] = "Bearer " + token;
            naglowki["Accept"] = "application/vnd.github+json";
        }

        var opcje = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => naglowki,
            :responseType => github
                ? Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                : Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };

        mZajety = true;
        try {
            Communications.makeWebRequest(url, null, opcje, method(:onOdpowiedz));
        } catch (e) {
            // Na CIQ < 7.0 pole danych dostanie tu wyjatek - nie ma sensu
            // probowac co 15 s, robota i tak nalezy do uslugi w tle.
            mZajety = false;
            mBezSieci = true;
            if (!PriceStore.zSieci()) {
                zapiszBlad("czekam na tlo");
            }
            return false;
        }
        return true;
    }

    // Sygnatura musi dokladnie pasowac do tego, czego oczekuje makeWebRequest
    function onOdpowiedz(
        kod as Lang.Number,
        dane as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null
    ) as Void {
        mZajety = false;
        var tekst = null;

        if (kod == 200) {
            if (dane instanceof Lang.String) {
                tekst = dane;
            } else if (dane instanceof Lang.Dictionary && dane["content"] != null) {
                tekst = dekodujBase64(dane["content"]);
            }
        }

        if (tekst != null && zapisz(tekst)) {
            zapiszBlad(null);
        } else if (kod == 200) {
            zapiszBlad("zly format");
        } else {
            zapiszBlad("HTTP " + kod);
        }

        koniec();
    }

    // --- parsowanie -----------------------------------------------------

    // Pobrany plik ma linie dwoch rodzajow:
    //
    //     2026-08-09,7.25     <- cena (liczy sie OSTATNIA taka linia, wiec
    //                            plik z cala historia tez zadziala)
    //     spalanie=6.4        <- moje ustawienia, dopisywane przez skrypt
    //     cel=20              <- z data/moje-ustawienia.txt w repo
    //
    // Dzieki temu spalanie i cel zmieniam edytujac plik na GitHubie, bez
    // przekompilowywania - przy wgraniu recznym (sideload) ustawienia
    // z telefonu i tak nie dzialaja.
    hidden function zapisz(tekst as Lang.String) as Lang.Boolean {
        var data = null;
        var cena = null;
        var spalanie = null;
        var cel = null;

        var reszta = tekst;
        while (reszta != null && reszta.length() > 0) {
            var nl = reszta.find("\n");
            var linia;
            if (nl != null) {
                linia = reszta.substring(0, nl);
                reszta = reszta.substring(nl + 1, reszta.length());
            } else {
                linia = reszta;
                reszta = "";
            }
            linia = bezBialych(linia);

            if (linia.length() >= 12 && linia.substring(4, 5).equals("-")) {
                // format sztywny: YYYY-MM-DD<separator>cena
                var c = przecinekNaKropke(linia.substring(11, linia.length())).toFloat();
                if (c != null && c > 0.0 && c < 100.0) {
                    data = linia.substring(0, 10);
                    cena = c;
                }
            } else if (zaczynaSie(linia, "spalanie=")) {
                var s = wartoscPo(linia, 9);
                if (s != null && s > 0.0 && s < 50.0) {
                    spalanie = s;
                }
            } else if (zaczynaSie(linia, "cel=")) {
                var t = wartoscPo(linia, 4);
                if (t != null && t >= 0.0 && t <= 1000.0) {
                    cel = t;
                }
            }
        }

        if (cena == null) {
            return false;
        }
        try {
            Storage.setValue(PriceStore.KEY_CENA, cena);
            Storage.setValue(PriceStore.KEY_DATA, data);
            Storage.setValue(PriceStore.KEY_POBRANO, Time.now().value());
            // Brak linii w pliku = kasujemy zapamietana wartosc i wracamy
            // do ustawien/Config, zamiast trzymac starocie w nieskonczonosc.
            zapiszLubSkasuj(PriceStore.KEY_SPALANIE, spalanie);
            zapiszLubSkasuj(PriceStore.KEY_CEL, cel);
        } catch (e) {
            return false;
        }
        return true;
    }

    hidden function zaczynaSie(s as Lang.String, przedrostek as Lang.String) as Lang.Boolean {
        if (s.length() < przedrostek.length()) {
            return false;
        }
        return s.substring(0, przedrostek.length()).equals(przedrostek);
    }

    hidden function wartoscPo(linia as Lang.String, od as Lang.Number) as Lang.Float or Null {
        return przecinekNaKropke(bezBialych(linia.substring(od, linia.length()))).toFloat();
    }

    hidden function zapiszLubSkasuj(klucz as Lang.String, wartosc) as Void {
        if (wartosc == null) {
            Storage.deleteValue(klucz);
        } else {
            Storage.setValue(klucz, wartosc);
        }
    }

    hidden function bezBialych(s as Lang.String) as Lang.String {
        // obcinamy \r i spacje z konca oraz spacje z poczatku
        var a = 0;
        var b = s.length();
        while (a < b && (s.substring(a, a + 1).equals(" "))) {
            a++;
        }
        while (b > a) {
            var c = s.substring(b - 1, b);
            if (c.equals("\r") || c.equals(" ") || c.equals("\t")) {
                b--;
            } else {
                break;
            }
        }
        return s.substring(a, b);
    }

    hidden function przecinekNaKropke(s as Lang.String) as Lang.String {
        var i = s.find(",");
        while (i != null) {
            s = s.substring(0, i) + "." + s.substring(i + 1, s.length());
            i = s.find(",");
        }
        return s;
    }

    // odpowiedz z api.github.com: pole "content" to base64 z lamaniem linii
    hidden function dekodujBase64(b64) as Lang.String or Null {
        if (!(b64 instanceof Lang.String)) {
            return null;
        }
        var s = b64;
        var i = s.find("\n");
        while (i != null) {
            s = s.substring(0, i) + s.substring(i + 1, s.length());
            i = s.find("\n");
        }
        try {
            return StringUtil.convertEncodedString(s, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
            });
        } catch (e) {
            return null;
        }
    }

    // --- reszta ---------------------------------------------------------

    hidden function zapiszBlad(tekst as Lang.String or Null) as Void {
        try {
            if (tekst == null) {
                Storage.deleteValue(PriceStore.KEY_BLAD);
            } else {
                Storage.setValue(PriceStore.KEY_BLAD, tekst);
            }
        } catch (e) {
        }
    }

    // Usluga w tle musi sama sie zamknac; na pierwszym planie nic nie robimy -
    // pole danych i tak przerysowuje sie co sekunde i odczyta nowa cene.
    hidden function koniec() as Void {
        if (mWTle) {
            try {
                Background.exit(null);
            } catch (e) {
            }
        }
    }
}
