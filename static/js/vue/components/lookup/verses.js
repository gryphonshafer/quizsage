import template from 'modules/template';

export default {
    data() {
        const material   = this.$root.material;
        const references = [];

        material.data.ranges.forEach( range => {
            range.verses.forEach( reference => {
                const found = reference.match(/^(?<book>.+)\s(?<chapter>\d+):(?<verse>\d+)$/);
                let book    = references.find( element => element.book == found.groups.book );

                if ( ! book ) {
                    book = {
                        book    : found.groups.book,
                        chapters: {},
                    };
                    references.push(book);
                }

                book.chapters[ found.groups.chapter ] ||= {};
                book.chapters[ found.groups.chapter ][ found.groups.verse ] = 1;
            } );
        } );

        references.forEach( book => {
            Object.keys( book.chapters ).forEach( chapter => {
                book.chapters[chapter] = Object.keys( book.chapters[chapter] );
            } );
        } );

        return {
            material  : material,
            references: references,
            books     : references.map( element => element.book ),
            selected  : {
                bible  : material.bibles[0].name,
                book   : references[0].book,
                chapter: Object.keys( references[0].chapters )[0],
                verse  : references[0].chapters[ Object.keys( references[0].chapters )[0] ][0],
            },
        };
    },

    computed: {
        chapters() {
            return Object.keys( this.references.find( book => book.book == this.selected.book ).chapters );
        },
        verses() {
            return this.references
                .find( book => book.book == this.selected.book )
                .chapters[ this.selected.chapter ];
        },
        reference() {
            return this.selected.book + ' ' + this.selected.chapter + ':' + this.selected.verse;
        },
        content() {
            return this.material.lookup(
                this.selected.bible,
                this.selected.book,
                this.selected.chapter,
            );
        },
    },

    watch: {
        'selected.book': function () {
            this.selected.chapter = this.chapters[0];
        },
        'selected.chapter': function () {
            this.selected.verse = this.verses[0];
        },
    },

    template: await template( import.meta.url ),
};
