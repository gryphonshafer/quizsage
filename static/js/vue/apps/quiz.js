import timer    from 'vue/components/timer';
import template from 'modules/template';

Vue
    .createApp({
        components: {
            timer,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#quiz');
