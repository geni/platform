// The host application's JS SDK, which /platform/admin/clientsdk is a test harness for.  The gem
// ships its own javascripts under app/assets/javascripts/platform but not this one: Geni serves
// lib/geni-connect.js from its own asset tree.  This is the dummy application's stand-in so the
// page has something to include.
window.Geni = window.Geni || {Auth: {}, Event: {}, api: function() {}};
