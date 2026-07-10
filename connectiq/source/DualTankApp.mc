using Toybox.Application;
using Toybox.WatchUi;

// Entry point for the Dual-Tank Anaerobic Reserve data field.
class DualTankApp extends Application.AppBase {

    hidden var mView;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    // A data field returns its view (and optional delegate) here.
    function getInitialView() {
        mView = new DualTankView();
        return [ mView ];
    }

    // Forward Connect IQ app-settings changes to the view so it reloads params live.
    function onSettingsChanged() {
        if (mView != null) {
            mView.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
