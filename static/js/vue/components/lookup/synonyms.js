import flag     from 'modules/flag';
import template from 'modules/template';

export default {
    data() {
        return {
            text     : '',
            thesaurus: Object.keys( this.$root.material.data.thesaurus ).map( term => {
                return {
                    term    : term,
                    text    : term.toLowerCase(),
                    meanings: this.$root.material.data.thesaurus[term],
                };
            } ),
        };
    },

    computed: {
        content() {
            const text = this.text
                .toLowerCase()
                .replace( /^\s+|\s+$/g, '' )
                .replace( /[^\w\s]/g, '' );

            const entry = this.thesaurus.find( item => item.text == text );

            return ( entry && typeof entry.meanings === 'string' )
                ? this.thesaurus.find( item => item.term == entry.meanings )
                : entry;
        },
    },

    methods: {
        flag() {
            if ( this.content ) flag( {
                source: 'synonyms',
                data  : this.content,
            } );
        },
    },

    template: await template( import.meta.url ),
};
