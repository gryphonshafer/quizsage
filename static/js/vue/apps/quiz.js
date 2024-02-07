import board    from 'vue/components/board';
import controls from 'vue/components/controls';
import material from 'vue/components/material';
import query    from 'vue/components/query';
import search   from 'vue/components/search';
import template from 'modules/template';
import timer    from 'vue/components/timer';

Vue
    .createApp({
        components: {
            board,
            controls,
            material,
            query,
            search,
            timer,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#quiz');
