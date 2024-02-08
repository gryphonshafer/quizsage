import board    from 'vue/components/board';
import template from 'modules/template';

Vue
    .createApp({
        components: {
            board,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#board');
