import material from 'vue/components/material';
import query    from 'vue/components/query';
import controls from 'vue/components/controls';
import search   from 'vue/components/search';
import template from 'modules/template';
import timer    from 'vue/components/timer';

Vue
    .createApp({
        components: {
            material,
            query,
            controls,
            search,
            timer,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#drill');
