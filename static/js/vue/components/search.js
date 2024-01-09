import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    data() {
        return {
            selected_bible: undefined,
            text          : '',
            exact         : false,
            matched_verses: [],
        };
    },

    computed: {
        ...Pinia.mapState( quiz, [ 'material', 'selected' ] ),
    },

    created() {
        this.selected_bible = this.selected.bible;
    },

    methods: {
        search_material() {
            this.matched_verses = [];
            if ( this.text.length > 3 ) {
                this.matched_verses = this.material.search(
                    this.text,
                    this.selected_bible,
                    ( this.exact ) ? 'exact' : 'inexact',
                );
            }
        },
    },

    watch: {
        'selected.bible'() {
            this.selected_bible = this.selected.bible;
        },
        selected_bible() {
            this.search_material();
        },
        text() {
            this.search_material();
        },
        exact() {
            this.search_material();
        }
    },

    template: await template( import.meta.url ),
};
