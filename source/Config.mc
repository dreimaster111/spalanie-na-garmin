// Wartosci domyslne / awaryjne.
//
// Ustawienia z telefonu (Connect IQ -> ustawienia pola danych) dzialaja TYLKO
// dla apek zainstalowanych ze sklepu CIQ. Przy wgraniu recznym (sideload)
// program korzysta z wartosci ponizej, wiec to tutaj wpisujesz swoje dane
// i przekompilowujesz.
//
// Modul jest oznaczony (:background), bo korzysta z niego rowniez usluga
// pobierajaca cene w tle (ma osobna, mala pule pamieci - 32 kB).
(:background)
module Config {
    // Adres pliku z cena paliwa. Publiczne repo -> raw.githubusercontent.com
    // (bez tokenu). Repo prywatne -> adres api.github.com/... + token nizej.
    const DEFAULT_URL = "https://raw.githubusercontent.com/dreimaster111/spalanie-na-garmin/main/data/pb95.txt";

    // Token GitHub PAT - potrzebny TYLKO dla repo prywatnego (api.github.com).
    const DEFAULT_TOKEN = "";

    // Srednie spalanie auta, z ktorym porownujemy jazde rowerem [l/100 km].
    // Faktyczne spalanie auta uzytkownika - liczy sie zanim zegarek pobierze
    // plik z linia "spalanie=" (i gdyby tej linii w pliku zabraklo).
    const DEFAULT_SPALANIE = 6.5;

    // Cena awaryjna [zl/l] - uzywana, gdy nic jeszcze nie pobrano z internetu.
    const DEFAULT_CENA = 7.20;

    // Cel oszczednosci na jeden przejazd [zl] - do paska postepu.
    // 0 = pasek w ogole sie nie rysuje.
    const DEFAULT_CEL = 15.0;

    // Ile kg CO2 daje spalenie litra benzyny. 2,31 kg/l to wartosc przyjmowana
    // powszechnie dla benzyny silnikowej (sam dwutlenek ze spalania, bez
    // produkcji i transportu paliwa).
    const CO2_NA_LITR = 2.31;

    // Co ile sekund odswiezac cene (cena zmienia sie raz na dobe, wiec 6 h
    // z zapasem wystarcza). Usluga w tle budzi sie czesciej, ale jesli cena
    // jest swieza - natychmiast konczy prace.
    const ODSWIEZ_CO_SEK = 6 * 3600;

    // Co ile sekund system ma budzic usluge w tle (min. 5 minut wg SDK).
    const BUDZIK_SEK = 3600;
}
