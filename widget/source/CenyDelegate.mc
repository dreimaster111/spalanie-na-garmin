using Toybox.Lang;
using Toybox.WatchUi;

// Gora/dol (przyciski albo przewijanie dotykiem) przesuwa zaznaczony dzien.
class CenyDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView as CenyView;

    function initialize(view as CenyView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onNextPage() as Lang.Boolean {
        mView.przesun(-1);      // "nastepna strona" = starszy dzien (w lewo)
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        mView.przesun(1);       // nowszy dzien (w prawo)
        return true;
    }

    function onSelect() as Lang.Boolean {
        CenyDane.pobierz();     // START = odswiez z sieci
        return true;
    }
}
