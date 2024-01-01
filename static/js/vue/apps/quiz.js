import quiz     from 'vue/components/quiz';
import template from 'modules/template';

Vue
    .createApp({
        components: {
            quiz,
        },
        template: await template( import.meta.url ),
    })
    .use( Pinia.createPinia() )
    .mount('#quiz');
