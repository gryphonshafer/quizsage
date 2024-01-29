import template  from 'modules/template';
import quiz      from 'vue/stores/quiz';
import thesaurus from 'vue/components/thesaurus';

export default {
    components: {
        thesaurus,
    },

    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'eligible_teams', 'is_quiz_done', 'last_event_if_not_viewed' ] ),
    },

    template: await template( import.meta.url ),
};
