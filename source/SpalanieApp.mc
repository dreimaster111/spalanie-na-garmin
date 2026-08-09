using Toybox.Application;
using Toybox.Background;
using Toybox.System;
using Toybox.Time;
using Toybox.Lang;

// Punkt startowy pola danych.
//
// Cala klasa (i wszystko, do czego siega jej konstruktor) musi byc oznaczona
// (:background), bo ten sam obiekt aplikacji jest tworzony rowniez przez
// usluge pobierajaca cene w tle.
(:background)
class SpalanieApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
        zarejestrujTlo();
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

    // Widok pola danych pokazywany w trakcie treningu
    function getInitialView() {
        return [ new SpalanieView() ];
    }

    // Usluga budzona przez system - pobiera cene nawet wtedy, gdy nie jedziemy
    function getServiceDelegate() {
        return [ new PriceService() ];
    }

    // Po zmianie ustawien w telefonie kasujemy znacznik pobrania, zeby cena
    // (a wlasciwie adres, z ktorego ja bierzemy) odswiezyla sie od razu.
    function onSettingsChanged() as Void {
        try {
            Application.Storage.deleteValue(PriceStore.KEY_POBRANO);
        } catch (e) {
        }
    }

    hidden function zarejestrujTlo() as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        try {
            if (Background.getTemporalEventRegisteredTime() == null) {
                Background.registerForTemporalEvent(new Time.Duration(Config.BUDZIK_SEK));
            }
        } catch (e) {
            // urzadzenie moze nie wspierac zdarzen czasowych - trudno,
            // zostaje pobieranie na starcie treningu
        }
    }
}
