import template from 'modules/template';

export default {
    data() {
        const references = [];

        this.$root.material.data.ranges.forEach( range => {
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
            material  : this.$root.material,
            references: references,
            selected  : {
                bible  : this.$root.material.bibles[0].name,
                book   : references[0].book,
                chapter: Object.keys( references[0].chapters )[0],
                verse  : references[0].chapters[ Object.keys( references[0].chapters )[0] ][0],
            },
        };
    },
    template: await template( import.meta.url ),
};
