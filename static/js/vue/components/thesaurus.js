import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    props: {
        type: String,
    },

    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'selected' ] ),

        items() {
            return ( this.type != 'text' )
                ? this.current.query[ 'detailed_' + this.type ]
                : this.current.materials
                    .find( material => material.bible.name == this.selected.bible )
                    .detailed_text;
        },
    },

    template: await template( import.meta.url ),
};
