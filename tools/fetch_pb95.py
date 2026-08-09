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


def zapisz(cena, data, zrodlo):
    os.makedirs(os.path.dirname(PLIK_CENA), exist_ok=True)

    # 1) plik dla zegarka - jedna krotka linia
    with open(PLIK_CENA, "w", encoding="ascii", newline="\n") as f:
        f.write("%s,%.2f\n" % (data, cena))

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

    cena, data, zrodlo = pobierz_cene()
    if cena is None:
        print("Nie udalo sie pobrac ceny z zadnego zrodla.", file=sys.stderr)
        return 1

    if args.dry_run:
        print("(dry-run) %s,%.2f" % (data, cena))
        return 0

    zapisz(cena, data, zrodlo)
    print("Zapisano %s -> %s,%.2f" % (PLIK_CENA, data, cena))
    return 0


if __name__ == "__main__":
    sys.exit(main())
