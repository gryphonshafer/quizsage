import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    data() {
        return {
            quiz: quiz(),
        };
    },
    template: await template( import.meta.url ),
};
