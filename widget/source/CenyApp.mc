using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

// Widget "Ceny Pb95": historia sredniej ceny benzyny 95 z ostatnich 30 dni.
// Dane pobiera z tego samego repo co pole danych (data/pb95-widget.txt).
// W przeciwienstwie do pola danych widget dostaje przyciski: gora/dol
// przesuwa zaznaczenie po dniach.
class CenyApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new CenyView();
        return [ view, new CenyDelegate(view) ];
    }
}
