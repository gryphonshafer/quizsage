import store    from 'vue/store';
import template from 'modules/template';

export default {
    props: {
        type: String,
    },

    computed: {
        ...Pinia.mapState( store, [ 'current', 'selected' ] ),

        items() {
            return ( this.type != 'text' )
                ? this.current.details[ this.type ]
                : this.current.materials
                    .find( material => material.bible.name == this.selected.bible )
                    .detailed_text;
        },
    },

    template: await template( import.meta.url ),
};
