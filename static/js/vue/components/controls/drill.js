import store    from 'vue/store';
import template from 'modules/template';

export default {
    computed: {
        ...Pinia.mapState( store, [ 'query_types', 'bibles', 'next_query_bible', 'add_verse' ] ),
    },

    methods: {
        ...Pinia.mapActions( store, [
            'create_query', 'set_next_query_bible', 'toggle_add_verse', 'exit_drill',
        ] ),
    },

    template: await template( import.meta.url ),
};
