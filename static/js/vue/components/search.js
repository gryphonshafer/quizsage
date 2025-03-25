import flag     from 'modules/flag';
import store    from 'vue/store';
import template from 'modules/template';

export default {
    data() {
        return {
            term          : '',
            matched_terms : [],
            text          : '',
            exact         : false,
            selected_bible: undefined,
            matched_verses: [],
        };
    },

    computed: {
        ...Pinia.mapState( store, [ 'material', 'selected', 'current' ] ),
    },

    created() {
        this.selected_bible = this.selected.bible;
    },

    methods: {
        search_terms() {
            this.matched_terms = [];
            if ( this.term.length > 2 ) {
                const matched_terms = this.material.synonyms_of_term( this.term );
                if ( matched_terms.length > 0 && matched_terms.length < 100 )
                    this.matched_terms = matched_terms;
            }
        },

        search_material() {
            this.matched_verses = [];
            if ( this.text.length > 3 ) {
                this.matched_verses = this.material.search(
                    this.text,
                    this.selected_bible,
                    ( this.exact ) ? 'exact' : 'inexact',
                );

                if ( this.matched_verses ) {
                    const query_verses = this.current.query.verse.toString().split('+');

                    const text_pattern = ( this.exact )
                        ? this.text
                        : this.material.text2words( this.text )[0].join('\\W+');

                    const search_regexp = new RegExp(
                        '(?=' + text_pattern + ')|(?<=' + text_pattern + ')',
                        ( this.exact ) ? undefined : 'i',
                    );

                    this.matched_verses.forEach( verse => {
                        verse.is_current_query = (
                            this.current.query.book == verse.book &&
                            this.current.query.chapter == verse.chapter &&
                            query_verses.find( number => number == verse.verse )
                        ) ? true : false;

                        verse.text_parts = verse.text
                            .split(search_regexp)
                            .map( part => {
                                return {
                                    text: part,
                                    type: ( part.match(search_regexp) ) ? 'match' : 'text',
                                };
                            } );
                    } );
                }
            }
        },

        reset() {
            this.term  = '';
            this.text  = '';
            this.exact = false;
        },

        flag(item) {
            flag( {
                source: 'thesaurus',
                data  : item,
            } );
        },
    },

    watch: {
        term() {
            this.search_terms();
        },
        text() {
            this.search_material();
        },
        exact() {
            this.search_material();
        },
        selected_bible() {
            this.search_material();
        },
        'selected.bible'() {
            this.selected_bible = this.selected.bible;
        },
    },

    template: await template( import.meta.url ),
};
