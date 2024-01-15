import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'selected' ] ),

        material() {
            return this.current.materials.find( material => material.bible.name == this.selected.bible );
        },
    },

    methods: {
        ...Pinia.mapActions( quiz, ['replace_query'] ),
    },

    template: await template( import.meta.url ),
};
