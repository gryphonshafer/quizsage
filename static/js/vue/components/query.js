import flag      from 'modules/flag';
import store     from 'vue/store';
import template  from 'modules/template';
import thesaurus from 'vue/components/thesaurus';

export default {
    components: {
        thesaurus,
    },

    computed: {
        ...Pinia.mapState( store, [
            'current', 'eligible_teams', 'is_quiz_done', 'last_event_if_not_viewed',
            'hidden_solution', 'toggle_hidden_solution', 'is_drill',
        ] ),
    },

    methods: {
        flag() {
            flag( {
                source: 'query',
                data  : this.current,
            } );
        },
    },

    template: await template( import.meta.url ),
};
