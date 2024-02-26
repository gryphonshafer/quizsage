import material         from 'vue/components/material';
import query            from 'vue/components/query';
import queries_controls from 'vue/components/queries_controls';
import search           from 'vue/components/search';
import template         from 'modules/template';

Vue
    .createApp({
        components: {
            material,
            query,
            queries_controls,
            search,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#queries');
