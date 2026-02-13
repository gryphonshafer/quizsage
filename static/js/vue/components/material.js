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
            'current', 'selected', 'hidden_solution', 'material',
        ] ),

        buffer() {
            return this.current.materials
                .find( material => material.bible.name == this.selected.bible )
                .buffer;
        },
    },

    methods: {
        display_label() {
            if ( window.omniframe && omniframe.memo ) {
                const canonical   = this.material.data.canonical.split('\)');
                const description = this.material.data.description.split('\)');

                const verses = [];
                const first_query = this.current.query.original || this.current.query;
                verses.push({
                    ref    : first_query.book + ' ' + first_query.chapter + ':' + first_query.verse,
                    aliases: this.material.aliases_lookup[
                        first_query.book + ' ' + first_query.chapter + ':' + first_query.verse
                    ] || ['<i>None</i>'],
                });
                if ( this.current.query.original ) {
                    const next_query = this.material.next_verse(
                        first_query.book, first_query.chapter, first_query.verse
                    );
                    verses.push({
                        ref    : next_query.book + ' ' + next_query.chapter + ':' + next_query.verse,
                        aliases: this.material.aliases_lookup[
                            next_query.book + ' ' + next_query.chapter + ':' + next_query.verse
                        ] || ['<i>None</i>'],
                    });
                }

                omniframe.memo({
                    class  : 'notice',
                    message:
                        [
                            verses.map( verse => {
                                return '<b>Label(s) containing ' + verse.ref + '</b> = ' +
                                    verse.aliases.join(', ');
                            } ).join('<br>\n'),

                            '<b>Quiz Label</b><br>' +
                            [
                                ...canonical.slice( 0, -1 ).map( part => part + ')' ),
                                ...canonical.slice(-1),
                            ].join('<br>\n'),

                            '<b>Quiz Description</b><br>' +
                            [
                                ...description.slice( 0, -1 ).map( part => part + ')' ),
                                ...description.slice(-1),
                            ].join('<br>\n'),

                            '<i>See also: ' +
                            '<a href="/docs/material_labels.md">Material Labels Documentation</a>' +
                            '</i>',
                        ].join('<br><br>'),
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
