using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

// Widget "Ceny Pb95": historia sredniej ceny benzyny 95 od poczatku roku.
// Dane pobiera z tego samego repo co pole danych (data/pb95-widget.txt).
// W przeciwienstwie do pola danych widget dostaje przyciski: gora/dol
// przesuwa zaznaczenie po dniach.
//
// (:glance) na klasie aplikacji jest wymagane, zeby system mogl ja
// zaladowac w trybie podgladu (glance) - tam trafia tylko kod z ta adnotacja.
(:glance)
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

    // Podglad na liscie glances: dzisiejsza cena + strzalka trendu.
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [ new CenyGlance() ];
    }
}
