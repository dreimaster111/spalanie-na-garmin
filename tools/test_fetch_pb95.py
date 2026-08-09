#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testy zachowania fetch_pb95.py w sytuacjach awaryjnych.

Sprawdzaja logike decyzyjna, a NIE same regexpy zrodel - zadne zapytanie
do internetu tu nie leci (pobierz_cene jest podmieniane), wiec test jest
szybki i nie wywali sie od tego, ze akurat ktorys serwis nie odpowiada.
Wszystko dzieje sie na plikach tymczasowych - pliki w data/ nie sa ruszane.

Uruchomienie:
    python tools/test_fetch_pb95.py

Kod wyjscia 0 = wszystko OK, 1 = ktorys przypadek nie przeszedl.
"""

import datetime
import importlib.util
import os
import sys
import tempfile

KATALOG_TOOLS = os.path.dirname(os.path.abspath(__file__))
SCIEZKA_SKRYPTU = os.path.join(KATALOG_TOOLS, "fetch_pb95.py")


def zaladuj(katalog):
    """Swieza kopia modulu z plikami przekierowanymi do katalogu tymczasowego."""
    spec = importlib.util.spec_from_file_location("fetch_pb95_pod_testem",
                                                  SCIEZKA_SKRYPTU)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.PLIK_CENA = os.path.join(katalog, "pb95.txt")
    m.PLIK_HISTORIA = os.path.join(katalog, "pb95-historia.csv")
    return m


def przygotuj(katalog, data, cena):
    with open(os.path.join(katalog, "pb95.txt"), "w", newline="\n") as f:
        f.write("%s,%.2f\n" % (data, cena))


def przypadek(nazwa, plik_na_starcie, wynik_zrodel, oczekiwany_kod, oczekiwany_plik):
    """
    plik_na_starcie - (data, cena) juz lezace w repo albo None
    wynik_zrodel    - co ma zwrocic pobierz_cene(): (cena, data, zrodlo)
    """
    with tempfile.TemporaryDirectory() as kat:
        if plik_na_starcie:
            przygotuj(kat, plik_na_starcie[0], plik_na_starcie[1])
        m = zaladuj(kat)
        m.pobierz_cene = lambda: wynik_zrodel

        sys.argv = ["fetch_pb95.py"]
        kod = m.main()

        tresc = None
        if os.path.exists(m.PLIK_CENA):
            with open(m.PLIK_CENA) as f:
                tresc = f.read().strip()

    ok = (kod == oczekiwany_kod) and (tresc == oczekiwany_plik)
    print("%-5s %-44s kod=%s plik=%r" % ("OK" if ok else "BLAD", nazwa, kod, tresc))
    if not ok:
        print("      oczekiwano: kod=%s plik=%r"
              % (oczekiwany_kod, oczekiwany_plik), file=sys.stderr)
    return ok


def main():
    dzis = datetime.date.today().isoformat()
    wczoraj = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
    dawno = (datetime.date.today() - datetime.timedelta(days=10)).isoformat()

    wyniki = [
        # Brak dzisiejszej ceny nie jest awaria - zegarek ma liczyc dalej
        # po wczorajszej, z jej prawdziwa data.
        przypadek("brak zrodel -> zostaje wczorajsza",
                  (wczoraj, 7.25), (None, None, None),
                  0, "%s,7.25" % wczoraj),

        # Pierwsze uruchomienie, ktore sie nie powiodlo - nie ma na czym jechac.
        przypadek("brak zrodel i brak pliku -> blad",
                  None, (None, None, None),
                  1, None),

        # Po tygodniu bez swiezej ceny czerwony Actions ma byc sygnalem.
        przypadek("brak zrodel, cena sprzed 10 dni -> blad",
                  (dawno, 7.25), (None, None, None),
                  1, "%s,7.25" % dawno),

        # Zaciety cache strony nie moze cofnac ceny.
        przypadek("zrodlo starsze niz plik -> bez zmian",
                  (dzis, 7.25), (7.10, wczoraj, "test"),
                  0, "%s,7.25" % dzis),

        # Zwykly, szczesliwy przypadek.
        przypadek("swieza cena -> zapis",
                  (wczoraj, 7.25), (7.40, dzis, "test"),
                  0, "%s,7.40" % dzis),
    ]

    print("\n%d/%d przypadkow OK" % (sum(wyniki), len(wyniki)))
    return 0 if all(wyniki) else 1


if __name__ == "__main__":
    sys.exit(main())
