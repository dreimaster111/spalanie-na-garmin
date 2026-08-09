using Toybox.System;
using Toybox.Background;
using Toybox.Lang;

// Usluga w tle: system budzi ja co godzine (Config.BUDZIK_SEK). Jesli cena
// jest wciaz swieza - natychmiast konczymy, zeby nie zjadac baterii.
// Uwaga: usluga ma tylko 32 kB pamieci i musi wywolac Background.exit()
// w ciagu 30 sekund, inaczej system ja ubija.
(:background)
class PriceService extends System.ServiceDelegate {

    // pole obiektu, a nie zmienna lokalna - inaczej odsmiecacz sprzatnalby
    // fetchera zanim przyjdzie odpowiedz z sieci
    hidden var mFetcher as PriceFetcher?;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        mFetcher = new PriceFetcher(true);
        if (!mFetcher.pobierzJesliStara()) {
            // nie ma czego pobierac (albo nie ma telefonu) - konczymy od razu
            Background.exit(null);
        }
    }
}
