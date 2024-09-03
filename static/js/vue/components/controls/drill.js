import store    from 'vue/store';
import template from 'modules/template';

export default {
    computed: {
        ...Pinia.mapState( store, [ 'query_types', 'bibles', 'next_query_bible', 'add_verse', 'auto_hide' ] ),
    },

    methods: {
        ...Pinia.mapActions( store, [
            'create_query', 'toggle_auto_hide', 'set_next_query_bible', 'toggle_add_verse', 'exit_drill',
        ] ),

        reset_create_query(query_type_key) {
            if ( this.$root.$refs.timer ) this.$root.$refs.timer.reset();
            this.create_query(query_type_key);
        }
    },

    template: await template( import.meta.url ),
};
