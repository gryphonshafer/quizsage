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
            'current', 'selected', 'hidden_solution', 'toggle_hidden_solution', 'material',
        ] ),

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

        display_label() {
            if ( window.omniframe && omniframe.memo ) {
                const canonical   = this.material.data.canonical.split('\)');
                const description = this.material.data.description.split('\)');

                omniframe.memo({
                    class: 'notice',
                    message:
                        '<p><b>Label:</b><br>' +
                        [
                            ...canonical.slice( 0, -1 ).map( part => part + ')' ),
                            ...canonical.slice(-1),
                        ].join('<br>\n') +
                        '<br><br><b>Description:</b><br>' +
                        [
                            ...description.slice( 0, -1 ).map( part => part + ')' ),
                            ...description.slice(-1),
                        ].join('<br>\n') +
                        '<br><br>' +
                        '<i>See also: ' +
                        '<a href="/docs/material_labels.md">Material Labels Documentation</a>' +
                        '</i>'
                });
            }
        },

        flag() {
            flag( {
                source: 'material',
                data  : this.current,
            } );
        },
    },

    template: await template( import.meta.url ),
};
