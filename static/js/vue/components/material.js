import quiz      from 'vue/store';
import template  from 'modules/template';
import thesaurus from 'vue/components/thesaurus';

export default {
    components: {
        thesaurus,
    },

    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'selected' ] ),
    },

    methods: {
        ...Pinia.mapActions( quiz, ['replace_query'] ),

        reset_replace_query() {
            if ( this.$root.$refs.controls ) this.$root.$refs.controls.trigger_event('reset');
            this.replace_query();
        },
    },

    template: await template( import.meta.url ),
};
