import material from 'vue/components/material';
import query    from 'vue/components/query';
import controls from 'vue/components/controls';
import search   from 'vue/components/search';
import template from 'modules/template';

Vue
    .createApp({
        components: {
            material,
            query,
            controls,
            search,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#drill');
