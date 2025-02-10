import store     from 'vue/store';
import template  from 'modules/template';
import thesaurus from 'vue/components/thesaurus';

export default {
    components: {
        thesaurus,
    },

    computed: {
        ...Pinia.mapState( store, [ 'current', 'selected', 'hidden_solution', 'toggle_hidden_solution', 'material' ] ),

        buffer() {
            return this.current.materials
                .find( material => material.bible.name == this.selected.bible )
                .buffer;
        },
    },

    methods: {
        ...Pinia.mapActions( store, ['replace_query'] ),

        reset_replace_query() {
            if ( this.$root.$refs.controls ) {
                this.$root.$refs.controls.trigger_event('reset');
            }
            else if ( this.$root.$refs.timer ) {
                this.$root.$refs.timer.reset();
            }
            this.replace_query();
        },

        display_description() {
            if ( window.omniframe && omniframe.memo ) {
                const parts = this.material.data.description.split('\)');
                omniframe.memo({
                    class   : 'notice',
                    messages: [ [
                        ...parts.slice( 0, -1 ).map( part => part + ')' ),
                        ...parts.slice(-1),
                    ] ],
                });
            }
        },
    },

    template: await template( import.meta.url ),
};
