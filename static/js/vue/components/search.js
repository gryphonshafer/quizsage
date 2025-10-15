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

        match_terms() {
            const synonyms_url = new URL( '../../synonyms', new URL( window.location.href ) );

            synonyms_url.searchParams.append( 'term', this.term );

            synonyms_url.searchParams.append( 'skip_substring_search', 1 );
            synonyms_url.searchParams.append( 'skip_term_splitting',   1 );
            synonyms_url.searchParams.append( 'direct_lookup',         1 );
            synonyms_url.searchParams.append( 'reverse_lookup',        1 );

            fetch(synonyms_url)
                .then( reply => reply.json() )
                .then( matches => {
                    this.matched_terms = matches
                        .map( match => {
                            return {
                                key     : match.text,
                                types   : match.types,
                                lookup  : match.lookup,
                                synonyms: {
                                    word    : match.text,
                                    meanings: match.meanings,
                                },
                            };
                        } );
                } );
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
                    const make_pattern = (text) => {
                        return ( this.exact )
                            ? text
                            : this.material.text2words(text)[0].join('\\W+');
                    };

                    const text_pattern  = make_pattern(this.text);
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

                        if ( verse.text.match(search_regexp) ) {
                            verse.text_parts = verse.text
                                .split(search_regexp)
                                .map( part => {
                                    return {
                                        text: part,
                                        type: ( part.match(search_regexp) ) ? 'match' : 'text',
                                    };
                                } );
                        }
                        else {
                            const wordsish = this.text.split(' ');
                            let search_regexp_first, search_regexp_next;

                            for ( let index = 1; index < wordsish.length; index++ ) {
                                const test_search_regexp_first = new RegExp(
                                    '(' + make_pattern( wordsish.slice( 0, index ).join(' ') ) +
                                        ( ( this.exact ) ? '' : '\\W*' ) + ')$',
                                    ( this.exact ) ? undefined : 'i',
                                );

                                const test_search_regexp_next = new RegExp(
                                    '^(' + ( ( this.exact ) ? '' : '\\W*' ) +
                                        make_pattern( wordsish.slice(index).join(' ') ) + ')',
                                    ( this.exact ) ? undefined : 'i',
                                );

                                if (
                                    verse.text.match(test_search_regexp_first) &&
                                    verse.text_next.match(test_search_regexp_next)
                                ) {
                                    search_regexp_first = test_search_regexp_first;
                                    search_regexp_next  = test_search_regexp_next;
                                    break;
                                }
                            }


                            verse.text_parts = [
                                ...verse.text
                                    .split(search_regexp_first)
                                    .map( part => {
                                        return {
                                            text: part,
                                            type: ( part.match(search_regexp_first) ) ? 'match' : 'text',
                                        };
                                    } ),
                                {
                                    type: 'reference',
                                    text:
                                        ' (' +
                                        ( ( verse.book != verse.book_next ) ? verse.book_next + ' ' : '' ) +
                                        (
                                            ( verse.chapter != verse.chapter_next )
                                                ? verse.chapter_next + ':'
                                                : ''
                                        ) +
                                        (
                                            (
                                                verse.book    == verse.book_next &&
                                                verse.chapter == verse.chapter_next
                                            ) ? 'v' : '' ) +
                                        verse.verse_next +
                                        ') ',
                                },
                                ...verse.text_next
                                    .split(search_regexp_next)
                                    .map( part => {
                                        return {
                                            text: part,
                                            type: ( part.match(search_regexp_next) )
                                                ? 'next_verse_match'
                                                : 'next_verse',
                                        };
                                    } ),
                            ];
                        }
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
