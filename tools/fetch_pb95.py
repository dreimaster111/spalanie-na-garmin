#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pobiera srednia cene benzyny Pb95 w Polsce i zapisuje ja w postaci, ktora
zegarek potrafi przeczytac za jednym zamachem:

    data/pb95.txt            -> jedna linia: 2026-08-09,7.25
    data/pb95-historia.csv   -> historia (data;cena;zrodlo), po jednej linii na dzien

Dlaczego przez posrednika, a nie prosto ze strony?
Kazdy serwis z cenami paliw to ~100 kB HTML-a. Usluga w tle w Connect IQ ma
32 kB pamieci - takiej strony fizycznie nie ma gdzie wczytac, nie mowiac
o parsowaniu. Ten skrypt (uruchamiany raz dziennie przez GitHub Actions)
robi cala brudna robote na serwerze, a zegarek pobiera 16 bajtow.

Gdy zadne zrodlo nie odda dzis ceny, plik zostaje nietkniety - zegarek liczy
dalej po cenie z poprzedniego dnia, z jej PRAWDZIWA data (w stopce pola danych
widac wtedy, ze cena jest wczorajsza). Skrypt konczy sie wtedy sukcesem, zeby
nie zasypywac skrzynki mailami z Actions; dopiero po MAX_DNI_STAROSCI dniach
bez swiezej ceny zwraca blad, bo to znaczy, ze scraper naprawde wymaga poprawki.
Historia zawiera wylacznie faktycznie pobrane dni - braki nie sa uzupelniane
skopiowana cena.

Uruchomienie recznie:
    python tools/fetch_pb95.py
Tylko podglad, bez zapisu:
    python tools/fetch_pb95.py --dry-run

Skrypt korzysta wylacznie z biblioteki standardowej.
"""

import argparse
import datetime
import os
import re
import sys
import urllib.request

KATALOG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLIK_CENA = os.path.join(KATALOG, "data", "pb95.txt")
PLIK_HISTORIA = os.path.join(KATALOG, "data", "pb95-historia.csv")
PLIK_USTAWIEN = os.path.join(KATALOG, "data", "moje-ustawienia.txt")

# Klucze, ktore wolno przepuscic z moje-ustawienia.txt do pliku dla zegarka.
# Bialalista, zeby literowka w recznie edytowanym pliku nie wjechala na zegarek.
DOZWOLONE_USTAWIENIA = ("spalanie", "cel")

NAGLOWKI = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept-Language": "pl-PL,pl;q=0.9",
}

# Sensowny zakres ceny [zl/l] - odsiewa smieci wpadajace z regexpa
MIN_CENA = 3.0
MAX_CENA = 20.0

# Ile dni wolno jechac na starej cenie, zanim uznamy scraper za zepsuty
# i pozwolimy workflowowi sie wywalic (czerwony Actions = sygnal do poprawki).
MAX_DNI_STAROSCI = 7


def pobierz_html(url, timeout=30):
    req = urllib.request.Request(url, headers=NAGLOWKI)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "ignore")


def na_float(tekst):
    """'7,25' -> 7.25"""
    try:
        return float(tekst.replace(",", ".").strip())
    except (ValueError, AttributeError):
        return None


def sensowna(cena):
    return cena is not None and MIN_CENA <= cena <= MAX_CENA


# --- zrodla ---------------------------------------------------------------
# Kazde zrodlo zwraca (cena, data) albo (None, None).
# Data bierzemy ze strony, gdy ja podaje - dzieki temu wiadomo, "na ktory dzien"
# jest cena; w przeciwnym razie zostaje dzisiejsza.


def zrodlo_cenypaliw_fyi():
    """Tytul og:title zawiera komplet: 'PB95 7,25 zl/l, ON 8,03 zl/l (09.08.2026)'."""
    html = pobierz_html("https://cenypaliw.fyi/")
    m = re.search(r'og:title"\s+content="([^"]+)"', html)
    tytul = m.group(1) if m else html[:4000]

    mc = re.search(r"PB\s?95[^0-9]{0,12}(\d{1,2}[,.]\d{1,2})", tytul, re.I)
    if not mc:
        return None, None
    cena = na_float(mc.group(1))

    data = None
    md = re.search(r"\((\d{2})\.(\d{2})\.(\d{4})\)", tytul)
    if md:
        data = "%s-%s-%s" % (md.group(3), md.group(2), md.group(1))
    return cena, data


def zrodlo_autocentrum():
    """Tabela srednich cen krajowych."""
    html = pobierz_html("https://www.autocentrum.pl/paliwa/ceny-paliw/")
    # szukamy etykiety Pb95/95 i pierwszej liczby w rozsadnym formacie za nia
    for wzor in (
        r"Pb\s?95.{0,400}?(\d{1,2},\d{2})",
        r">\s*95\s*<.{0,400}?(\d{1,2},\d{2})",
    ):
        m = re.search(wzor, html, re.I | re.S)
        if m:
            cena = na_float(m.group(1))
            if sensowna(cena):
                return cena, None
    return None, None


def zrodlo_zapaliwo():
    """
    Strona ma w zrodle dane wojewodztw w formie JSON-a:
        ...,"date":"2026-08-09","voivodeship":"lodzkie","pb95":7.45,...
    Bierzemy najswiezsza date i liczymy srednia krajowa z wojewodztw.
    """
    html = pobierz_html("https://zapaliwo.pl/")
    pary = []
    for m in re.finditer(r'\\?"pb95\\?"\s*:\s*(\d{1,2}(?:\.\d+)?)', html):
        cena = na_float(m.group(1))
        if not sensowna(cena):
            continue
        # data stoi w tym samym rekordzie, kilkadziesiat znakow wczesniej
        okno = html[max(0, m.start() - 200):m.start()]
        md = re.findall(r"(\d{4}-\d{2}-\d{2})", okno)
        pary.append((md[-1] if md else None, cena))

    if not pary:
        return None, None

    daty = [d for d, _ in pary if d]
    if daty:
        najnowsza = max(daty)
        ceny = [c for d, c in pary if d == najnowsza]
    else:
        najnowsza = None
        ceny = [c for _, c in pary]

    if not ceny:
        return None, None
    return round(sum(ceny) / len(ceny), 2), najnowsza


ZRODLA = [
    ("cenypaliw.fyi", zrodlo_cenypaliw_fyi),
    ("zapaliwo.pl", zrodlo_zapaliwo),
    ("autocentrum.pl", zrodlo_autocentrum),
]


def pobierz_cene():
    """Probuje zrodla po kolei; zwraca (cena, data, nazwa_zrodla)."""
    bledy = []
    for nazwa, funkcja in ZRODLA:
        try:
            cena, data = funkcja()
        except Exception as e:  # padniete zrodlo nie moze wywrocic calego skryptu
            bledy.append("%s: %s" % (nazwa, e))
            continue
        if sensowna(cena):
            if not data:
                data = datetime.date.today().isoformat()
            print("OK  %-16s %s zl/l (%s)" % (nazwa, ("%.2f" % cena), data))
            return cena, data, nazwa
        bledy.append("%s: nie znalazlem ceny" % nazwa)

    for b in bledy:
        print("BLAD %s" % b, file=sys.stderr)
    return None, None, None


# --- zapis ----------------------------------------------------------------


def wczytaj_historie():
    if not os.path.exists(PLIK_HISTORIA):
        return {}
    wynik = {}
    with open(PLIK_HISTORIA, "r", encoding="utf-8") as f:
        for linia in f:
            czesci = linia.strip().split(";")
            if len(czesci) >= 2 and len(czesci[0]) == 10:
                wynik[czesci[0]] = linia.rstrip("\n")
    return wynik


def wczytaj_biezaca():
    """Co obecnie czyta zegarek: (data, cena) albo (None, None)."""
    if not os.path.exists(PLIK_CENA):
        return None, None
    with open(PLIK_CENA, "r", encoding="utf-8", errors="ignore") as f:
        linia = f.read().strip()
    czesci = linia.split(",")
    if len(czesci) == 2 and len(czesci[0]) == 10:
        return czesci[0], na_float(czesci[1])
    return None, None


def wiek_w_dniach(data_iso):
    try:
        d = datetime.date.fromisoformat(data_iso)
    except ValueError:
        return None
    return (datetime.date.today() - d).days


def wczytaj_moje_ustawienia():
    """
    Czyta data/moje-ustawienia.txt (edytowany recznie) i zwraca liste linii
    "klucz=wartosc" do doklejenia do pliku dla zegarka. Bledne linie pomija -
    plik jest edytowany palcami, wiec nie moze wywrocic aktualizacji ceny.
    """
    if not os.path.exists(PLIK_USTAWIEN):
        return []
    linie = []
    with open(PLIK_USTAWIEN, "r", encoding="utf-8", errors="ignore") as f:
        for surowa in f:
            surowa = surowa.strip()
            if not surowa or surowa.startswith("#") or "=" not in surowa:
                continue
            klucz, wartosc = surowa.split("=", 1)
            klucz = klucz.strip()
            if klucz not in DOZWOLONE_USTAWIENIA:
                print("  pomijam nieznane ustawienie: %s" % klucz, file=sys.stderr)
                continue
            liczba = na_float(wartosc)
            if liczba is None:
                print("  pomijam %s - '%s' to nie liczba" % (klucz, wartosc.strip()),
                      file=sys.stderr)
                continue
            linie.append("%s=%s" % (klucz, ("%.2f" % liczba).rstrip("0").rstrip(".")))
    return linie


def zapisz_dla_zegarka(cena, data):
    """
    Plik, ktory pobiera zegarek: linia z cena + moje ustawienia.
    Wolamy to takze wtedy, gdy ceny nie udalo sie odswiezyc - inaczej zmiana
    spalania czy celu nie dojechalaby do zegarka az do nastepnej nowej ceny.
    """
    os.makedirs(os.path.dirname(PLIK_CENA), exist_ok=True)
    ustawienia = wczytaj_moje_ustawienia()
    with open(PLIK_CENA, "w", encoding="ascii", newline="\n") as f:
        f.write("%s,%.2f\n" % (data, cena))
        for linia in ustawienia:
            f.write(linia + "\n")
    if ustawienia:
        print("Doklejone ustawienia: %s" % ", ".join(ustawienia))


def zapisz(cena, data, zrodlo):
    zapisz_dla_zegarka(cena, data)

    # 2) historia - jeden wpis na dzien (nowszy nadpisuje starszy)
    historia = wczytaj_historie()
    historia[data] = "%s;%.2f;%s" % (data, cena, zrodlo)
    with open(PLIK_HISTORIA, "w", encoding="utf-8", newline="\n") as f:
        for klucz in sorted(historia):
            f.write(historia[klucz] + "\n")


def main():
    p = argparse.ArgumentParser(description="Pobiera srednia cene Pb95 w Polsce")
    p.add_argument("--dry-run", action="store_true", help="tylko pokaz, nie zapisuj")
    args = p.parse_args()

    stara_data, stara_cena = wczytaj_biezaca()
    cena, data, zrodlo = pobierz_cene()

    # Zadne zrodlo nie oddalo ceny - zostawiamy to, co jest, czyli cene
    # z poprzedniego dnia. NIE podmieniamy jej daty na dzisiejsza: zegarek
    # pokazuje w stopce dzien, z ktorego cena pochodzi, wiec ma byc widac,
    # ze jest wczorajsza, zamiast udawac swieza.
    if cena is None:
        if stara_cena is None:
            print("Nie udalo sie pobrac ceny, a w repo nie ma zadnej poprzedniej.",
                  file=sys.stderr)
            return 1
        wiek = wiek_w_dniach(stara_data)
        print("Nie znalazlem dzisiejszej ceny - zostaje %.2f zl/l z %s (%s dni temu)."
              % (stara_cena, stara_data, wiek))
        if wiek is not None and wiek > MAX_DNI_STAROSCI:
            print("To juz ponad %d dni - scraper zapewne wymaga poprawki."
                  % MAX_DNI_STAROSCI, file=sys.stderr)
            return 1
        # cena zostaje ta sama, ale ustawienia moga sie zmienic
        if not args.dry_run:
            zapisz_dla_zegarka(stara_cena, stara_data)
        return 0

    # Serwis oddal cene starsza niz ta, ktora juz mamy (np. zacieta kopia
    # strony w cache) - nie cofamy sie.
    if stara_data is not None and data < stara_data:
        print("Zrodlo podalo cene z %s, a mamy juz swiezsza z %s - zostawiam bez zmian."
              % (data, stara_data))
        if not args.dry_run:
            zapisz_dla_zegarka(stara_cena, stara_data)
        return 0

    if args.dry_run:
        print("(dry-run) %s,%.2f" % (data, cena))
        return 0

    zapisz(cena, data, zrodlo)
    print("Zapisano %s -> %s,%.2f" % (PLIK_CENA, data, cena))
    return 0


if __name__ == "__main__":
    sys.exit(main())
