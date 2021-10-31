(function () {
    'use strict';
    //data bindings and data access
    $dyn.controls.WalkMePage = function (data, element) {
        $dyn.ui.Control.apply(this, arguments);
        $dyn.ui.applyDefaults(this, data, $dyn.ui.defaults.WalkMePage);
    };
    var value;    

   // Initialize the at walkmepage control startup.
    $dyn.controls.WalkMePage.prototype = $dyn.ui.extendPrototype($dyn.ui.Control.prototype, {
        init: function (data, element) {
            var self = this;

            // Prevent injecting WalkMe more than once
            if (window._walkmeConfig)
                return;

            $dyn.ui.Control.prototype.init.apply(this, arguments); // on intilizing the control
 
            var urlsite = data.URL; // Fetching the URL Site from Dynamics 365
                        
            if (urlsite)
            {
                //Injecting the Javascript code.
                var walkme = document.createElement('script');
                walkme.type = 'text/javascript';
                walkme.async = true;
                walkme.src = urlsite;
                var str = walkme.src;
                var pos = str.search(".js");
                value = str.substring(0, pos + 3);
                walkme.src = value;
                var s = document.getElementsByTagName('script')[0];
                s.parentNode.insertBefore(walkme, s);
                window._walkmeConfig = { smartLoad: true };                
            }
            
        }
        
    });
    
})();