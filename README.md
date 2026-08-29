# Oszczędność paliwa — pole danych Connect IQ (Fenix 6X Pro)

Pole danych pokazuje w trakcie treningu, **ile złotych zaoszczędziłeś**, jadąc
rowerem zamiast autem — licząc po **aktualnej średniej cenie benzyny 95**
pobieranej z internetu.

```
oszczędność [zł] = dystans [km] / 100 × spalanie auta [l/100 km] × cena Pb95 [zł/l]
```

Na ekranie (pole na cały ekran, czyli układ z jednym polem danych):

```
         Oszczędność            <- etykieta
                                
           12,34 zł             <- kwota największym fontem, jaki wchodzi
                                
      0,2 l    0,6 kg CO2       <- czego nie spaliliśmy
       7,32 zł/l 14.08          <- użyta cena i dzień, z którego pochodzi
   \_________________/          <- łuk postępu do celu, po dolnym obrzeżu
```

W wąskim kafelku (2, 3, 4 pola na ekranie) ten sam kod składa się do jednego
wiersza z kwotą, a z ozdób zostaje to, co się zmieści — łuk zamienia się wtedy
w zwykły poziomy pasek, bo potrzebuje całej tarczy.

Stopka na pomarańczowo + `?` = cena z internetu jeszcze nie dotarła, liczone
po cenie awaryjnej z ustawień. Zamiast daty może pojawić się krótki powód
(`brak telefonu`, `HTTP 404`).

Nad wierszem litrów może pojawić się jeszcze `razem 342 zł` — suma
oszczędności ze wszystkich jazd w bieżącym roku (liczona przyrostowo w trakcie
jazdy, zapisywana w Storage co pół minuty; 1 stycznia zeruje się sama).
Rysuje się tylko, gdy kwota główna ma dalej dość miejsca — w małych kaflach
odpada pierwsza.

Przy cenie w stopce może stać trójkącik trendu: czerwony w górę = benzyna
podrożała, zielony w dół = staniała. Kierunek pochodzi z porównania z
**ostatnią inną** ceną z historii — scraper dokleja ją do pliku dla zegarka
linią `poprzednia=6.58`.

### Okrągły ekran to nie prostokąt

Pole danych dostaje do rysowania **prostokąt**, ale na fenixie widać z niego
tylko to, co wpada w okrąg tarczy — z kafla 280×280 to 61 000 z 78 000 pikseli.
Napis dosunięty do dolnej krawędzi albo do boku zostaje więc obcięty przez
obrzeże, mimo że mieści się w `dc.getWidth()`.

Dlatego przy układzie na cały ekran szerokość każdego wiersza liczymy z
**cięciwy koła** na jego wysokości, a nie z szerokości kafla, i tak samo
dobieramy wysokość, na której siada etykieta i stopka. Że kafel to cały ekran,
poznajemy po `getObscurityFlags()` — gdy tarcza przycina wszystkie cztery
krawędzie, wiadomo na pewno, że środek koła leży w środku kafla, a promień to
połowa jego szerokości.

Dla wąskich pasów tej pewności nie ma: `OBSCURE_TOP` mówi tylko, że górne rogi
pasa są ścięte, ale nie o ile pas jest odsunięty od góry ekranu — a bez tego
środka koła nie da się umiejscowić. Pasy zostają więc przy prostokącie.

Łuk postępu jest przy okazji efektem ubocznym tej geometrii: obrzeże tarczy to
jedyne miejsce, gdzie duży wskaźnik nie zabiera pola głównej liczbie. Kąt 0°
jest na godzinie 3 i rośnie przeciwnie do wskazówek zegara, więc dolne półkole
to `drawArc(..., ARC_COUNTER_CLOCKWISE, 180, 359)` — wypełnienie płynie od
9:00 przez 6:00 do 3:00.

## Skąd bierze się cena

Zegarek **nie** pobiera ceny prosto ze strony WWW — każdy serwis z cenami paliw
to ~100 kB HTML-a, a usługa działająca w tle w Connect IQ ma tylko **32 kB**
pamięci. Nie ma tego gdzie wczytać, nie mówiąc o parsowaniu. Nie ma też
darmowego, publicznego API z ceną Pb95 bez klucza (sprawdzone: paliwo.today,
nakordoni.eu i OilPriceAPI wymagają rejestracji/klucza).

Dlatego robotę dzielimy na dwie części — dokładnie tak jak w widgecie wagi:

```
GitHub Actions (raz na 12 h)          zegarek (raz na 6 h)
tools/fetch_pb95.py  ───►  data/pb95.txt  ───►  usługa w tle ───► Storage ───► pole danych
   scrapuje serwisy          "2026-08-09,7.25"      16 bajtów
```

`tools/fetch_pb95.py` próbuje po kolei trzech źródeł (pierwsze, które zadziała,
wygrywa) i zapisuje wynik:

| źródło | co bierze | podaje datę |
|---|---|---|
| [cenypaliw.fyi](https://cenypaliw.fyi/) | średnia detaliczna PB95 z `og:title` | tak |
| [zapaliwo.pl](https://zapaliwo.pl/) | średnia z 16 województw (dane w JSON w źródle strony) | tak |
| [autocentrum.pl](https://www.autocentrum.pl/paliwa/ceny-paliw/) | średnia krajowa z tabeli | nie |

Wyniki na 09.08.2026: 7,25 / 7,30 / 7,30 zł/l — zgodne, więc awaryjne źródła
mają sens. Skrypt używa wyłącznie biblioteki standardowej Pythona.

Pliki wynikowe:

- `data/pb95.txt` — jedna linia dla zegarka: `2026-08-09,7.25`
- `data/pb95-historia.csv` — archiwum `data;cena;źródło` (po jednym wpisie na dzień)

### Gdy dzisiejszej ceny nie ma

Jeśli żadne źródło nie odda ceny, plik zostaje **nietknięty** — zegarek liczy
dalej po cenie z poprzedniego dnia, ale z jej **prawdziwą datą**, więc w stopce
pola danych widać, że jest wczorajsza. Data nie jest podmieniana na dzisiejszą
i historia nie jest uzupełniana skopiowaną ceną — w archiwum lądują wyłącznie
dni faktycznie pobrane.

Skrypt kończy się wtedy sukcesem (żeby Actions nie zasypywało skrzynki mailami),
ale po **7 dniach** bez świeżej ceny zwraca błąd — czerwony Actions jest wtedy
sygnałem, że któryś regex wymaga poprawki.

Pilnowany jest też przypadek odwrotny: gdyby serwis oddał cenę **starszą** niż
ta, którą już mamy (zacięty cache strony), zapis jest pomijany — nigdy się nie
cofamy.

Te reguły są pokryte testem, który Actions odpala **przed** scraperem:

```bash
python tools/test_fetch_pb95.py
```

Test nie rusza sieci (podmienia `pobierz_cene`) ani plików w `data/` — pracuje
na katalogu tymczasowym, więc jest szybki i nie wywali się od tego, że akurat
któryś serwis nie odpowiada. Regexpy źródeł weryfikuje dopiero prawdziwe
uruchomienie scrapera.

Ręczne uruchomienie:

```bash
python tools/fetch_pb95.py
```

Podgląd bez zapisu:

```bash
python tools/fetch_pb95.py --dry-run
```

## Co trzeba zrobić raz, żeby cena chodziła sama

1. Załóż na GitHubie **publiczne** repo `spalanie-na-garmin` i wypchnij do niego
   ten projekt (workflow `.github/workflows/pb95.yml` odpali się sam, 2× dziennie;
   można też ręcznie z zakładki *Actions*).
2. Sprawdź, że plik jest widoczny pod adresem:
   `https://raw.githubusercontent.com/<twoj-login>/spalanie-na-garmin/main/data/pb95.txt`
3. Wpisz ten adres w `source/Config.mc` → `DEFAULT_URL` i przekompiluj.

Jeśli wolisz repo **prywatne**: podaj w `DEFAULT_URL` adres
`https://api.github.com/repos/<login>/<repo>/contents/data/pb95.txt`
i wpisz token PAT w `DEFAULT_TOKEN` — program rozpoznaje ten wariant po
adresie i sam rozkoduje base64 (tak jak widget wagi).

## Ustawienia

| ustawienie | domyślnie | opis |
|---|---|---|
| Spalanie auta | 7,0 l/100 km | z czym porównujemy rower |
| Cena awaryjna | 7,20 zł/l | używana, dopóki nic nie pobrano |
| Adres pliku z ceną | (puste → `Config.DEFAULT_URL`) | |
| Token GitHub | (puste) | tylko dla repo prywatnego |

**Uwaga:** ustawienia z telefonu (aplikacja Connect IQ) działają tylko dla apek
zainstalowanych ze sklepu CIQ. Przy wgraniu ręcznym (sideload) telefon ich nie
pokaże. W symulatorze działają: *File → Edit Application.Properties*.

### Zmiana spalania i celu bez rekompilacji

Żeby dało się je zmieniać mimo sideloadu, spalanie i cel jadą **tym samym
plikiem, co cena**. Edytujesz `data/moje-ustawienia.txt` (bot go nie rusza):

```
spalanie=6.4
cel=20
```

`fetch_pb95.py` dokleja te linie do `data/pb95.txt`, więc zegarek dostaje:

```
2026-08-09,7.25
spalanie=6.4
cel=20
```

Zmiana działa po przeleceniu workflow (2× dziennie albo ręcznie z *Actions*)
i kolejnym pobraniu przez zegarek. Klucze spoza białej listy i wartości, które
nie są liczbą, są pomijane — literówka w ręcznie edytowanym pliku nie wjedzie
na zegarek ani nie wywróci aktualizacji ceny. Plik dla zegarka jest przepisywany
także wtedy, gdy ceny nie udało się odświeżyć, żeby zmiana ustawień dojechała
niezależnie od tego, czy serwisy z cenami akurat działają.

Kolejność źródeł w apce: **pobrany plik → ustawienia z telefonu → `Config.mc`**.
Plik wygrywa, bo przy sideloadzie jest jedyną drogą, żeby cokolwiek zmienić.

## Struktura

```
manifest.xml              # datafield, fenix6xpro + fenix6pro/6spro + fenix8; uprawnienia: Communications, Background
monkey.jungle
source/
  SpalanieApp.mc          # AppBase: widok + rejestracja usługi w tle
  SpalanieView.mc         # rysowanie pola (onUpdate: geometria tarczy, luk, font do kafelka)
  PriceService.mc         # ServiceDelegate — budzony przez system co godzinę
  PriceFetcher.mc         # makeWebRequest + parsowanie linii "data,cena"
  PriceStore.mc           # wspólny dostęp do Storage i do ustawień
  Config.mc               # wartości domyślne/awaryjne (adres, token, spalanie, cena)
resources/                # teksty, ustawienia, ikona
tools/fetch_pb95.py       # scraper ceny (uruchamiany przez Actions)
tools/test_fetch_pb95.py  # testy logiki awaryjnej, bez sieci (Actions odpala je przed scraperem)
data/pb95.txt             # to, co czyta zegarek
.github/workflows/pb95.yml
```

### Dlaczego usługa w tle, a nie zwykłe pobieranie

**Na fenixie 6X to jedyna działająca droga.** Pola danych dostały bezpośredni
dostęp do modułu `Communications` dopiero w **Connect IQ System 7** (changelog
SDK v7.0.0.beta1: *„Allow data fields to use the Communications module […]
without having to use backgrounding"*). Fenix 6X Pro ma CIQ **3.4.5**, więc
obowiązuje go starsza zasada z FAQ SDK: *„a watch face or data field that can't
do communications itself, but the background process can"*.

Dlatego cenę przynosi `PriceService`: budzi się co godzinę, sprawdza czy cena
jest starsza niż 6 h i tylko wtedy sięga do sieci — wartość jest gotowa, zanim
wsiądziesz na rower. Pole danych dodatkowo próbuje pobrać cenę samo (3. sekunda
treningu i co 15 s) — to zadziała dopiero na fenixie 8; na 6X pierwsza próba
kończy się wyjątkiem, po którym `PriceFetcher` ustawia `mBezSieci` i przestaje
zawracać głowę. Obie ścieżki piszą do tego samego `Storage`, więc wynik jest
ten sam niezależnie od tego, która zadziałała.

Cała klasa aplikacji, usługa i `PriceFetcher` są oznaczone `(:background)` —
inaczej kompilator nie wpuściłby ich do 32-kilobajtowej puli pamięci tła.

## Kompilacja

```bash
"$HOME/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2/bin/monkeyc.bat" -f monkey.jungle -o bin/spalanie.prg -d fenix6xpro -y developer_key.der
```

W VS Code z rozszerzeniem Monkey C wystarczy **F5** (konfiguracje dla Fenixa 6X
i 8 są w `.vscode/launch.json`).

Wgranie na zegarek (sideload): podłącz Fenixa po USB i skopiuj `.prg`
do `GARMIN/Apps`, a potem dodaj pole danych do ekranu treningowego
(Ustawienia → Aktywności → Rower → Ekrany danych → pola Connect IQ).

Zbudowane i sprawdzone dla: fenix6xpro, fenix6pro, fenix6spro, fenix843mm,
fenix847mm, fenix8solar47mm, fenix8solar51mm.

## Znane ograniczenia

- Pobieranie wymaga połączenia z telefonem (Bluetooth). Bez niego pole liczy
  po ostatniej zapisanej cenie — data w stopce pokazuje, jak stara jest.
- Na fenixie 6X cena przychodzi **wyłącznie** z usługi w tle (patrz wyżej),
  a system sam decyduje, kiedy ją obudzić. Pierwszy raz cena może więc pojawić
  się dopiero po godzinie od zainstalowania pola — do tego czasu stopka pokazuje
  cenę awaryjną i `?`.
- Serwisy z cenami to strony WWW, nie API — mogą zmienić układ. Wtedy poprawia
  się jeden regex w `tools/fetch_pb95.py`, bez ruszania kodu na zegarku.
- Cena to **średnia krajowa**, nie cena Twojej stacji.
