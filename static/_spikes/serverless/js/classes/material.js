import {min_verity_level} from 'modules/constants';

const json_material_path = '../../../../json/material';

export default class Material {
    constructor (label) {
        this.label = label;
        this.path  = this.label2path( this.label );
        this.ready = fetch( new URL( this.path, import.meta.url ) )
            .then( reply => reply.json() )
            .then( loaded_data => {
                this.loaded_data     = loaded_data;
                this.bibles_sequence = this.bibles();

                this.all_verses = this.loaded_data.blocks.flatMap( block =>
                    Object.keys( block.content ).flatMap( bible =>
                        block.content[bible].map( verse => ( { ...verse, bible: bible } ) )
                    )
                )
                .filter( ( verse, index, self ) =>
                    index === self.findIndex( this_verse =>
                        this_verse.bible   === verse.bible   &&
                        this_verse.book    === verse.book    &&
                        this_verse.chapter === verse.chapter &&
                        this_verse.verse   === verse.verse
                    )
                );

                this.verses_by_bible = {};
                this.loaded_data.bibles.forEach( bible =>
                    this.verses_by_bible[bible] = this.loaded_data.blocks.flatMap( block =>
                        block.content[bible].map( verse => ( { ...verse, bible: bible } ) )
                    )
                    .filter( ( verse, index, self ) =>
                        index === self.findIndex( this_verse =>
                            this_verse.book    === verse.book    &&
                            this_verse.chapter === verse.chapter &&
                            this_verse.verse   === verse.verse
                        )
                    )
                );

                return this;
            } );
    }

    // convert material label into JSON filename
    label2path( label = this.label ) {
        return json_material_path + '/' + label
            .replace( / /g,  '_' )
            .replace( /\(/g, '{' )
            .replace( /\)/g, '}' )
            .replace( /;/g,  '+' )
            .replace( /:/g,  '%' ) + '.json';
    }

    // shuffled bibles sequence
    bibles() {
        return this.loaded_data.bibles
            .map( value => ( { value, sort: Math.random() } ) )
            .sort( ( a, b ) => a.sort - b.sort )
            .map( ( {value} ) => value );
    }

    // next bible in an object-level shuffled sequence
    next_bible() {
        this.bibles_sequence.push( this.bibles_sequence.shift() );
        return this.bible();
    }

    // current bible
    bible() {
        return this.bibles_sequence[ this.bibles_sequence.length - 1 ];
    }

    // verses from a random-by-weight block given a bible (or the next bible in sequence)
    verses( bible = this.next_bible() ) {
        bible = bible.toUpperCase();
        if ( this.loaded_data.bibles.filter( item => item == bible ).length != 1 )
            throw '"' + bible + '" is not a valid Bible';

        const weights = this.loaded_data.blocks
            .map( ( block, index ) => Array( block.weight ).fill(index) )
            .flatMap( value => value );

        return this.loaded_data.blocks[
            weights[ Math.floor( Math.random() * weights.length ) ]
        ].content[bible];
    }

    // verse(s) given a bible, book, chapter (and optionally verse number)
    lookup( bible, book, chapter, verse_number = undefined ) {
        return this.loaded_data.blocks
            .flatMap( block => block.content[bible] )
            .filter( this_verse =>
                book    == this_verse.book    &&
                chapter == this_verse.chapter &&
                ( ! verse_number || verse_number == this_verse.verse )
            )
            .filter( ( verse, index, self ) =>
                index === self.findIndex( this_verse =>
                    this_verse.book    === verse.book    &&
                    this_verse.chapter === verse.chapter &&
                    this_verse.verse   === verse.verse
                )
            );
    }

    // split a text string into pure lowercase words
    static text2words(text) {
        return text
            // remove single-quotes from around words/phrases
            .replaceAll( /(^|\W)'(\w.*?)'(\W|$)/g, '$1$2$3')
            // remove commas, colons, and dashes at end of lines
            .replaceAll( /[,:\-]+$/g, '')
            // remove commas followed by single-quote
            .replaceAll( /,'/g, '')
            // remove commas and colons except for "1,234" and "3:00"
            .replaceAll( /[,:](?=\D)/g, '')
            // remove all but "usable" characters
            .replaceAll( /[^A-Za-z0-9'\-,:]/gi,    ' ')
            // convert dashes between numbers into spaces
            .replaceAll( /(\d)\-(\d)/g, '$1 $2')
            // remove single-quote following a non-word character
            .replaceAll( /(?<!\w)'/g, ' ')
            // remove single-quote following a word character prior to a non-word
            .replaceAll( /(\w)'(?=\W|$)/g, '$1')
            // convert double-dashes into spaces
            .replaceAll( /\-{2,}/g, ' ')
            // compact multi-spaces
            .replaceAll( /\s+/g, ' ')
            // trim spacing
            .replaceAll( /(?:^\s|\s$)/g, '')
            .toLowerCase()
            .split(/\s/);
    }

    // search for verses given a substring
    //     type "inexact" = match lower-case words of input against verse.string
    //     type "exact"   = match input against verse.text
    //     type "prompt"  = match lower-case words of input against verse.string with boundary edges
    search( input, bible = undefined, type = 'inexact' ) {
        if ( type == 'inexact' ) input = Material.text2words(input).join(' ').toLowerCase();

        let boundary_regex = ( type == 'prompt' ) ? new RegExp( '\\b' + input + '\\b' ) : null;

        return ( ( ! bible ) ? this.all_verses : this.verses_by_bible[bible] )
            .filter( verse =>
                ( type == 'exact'  ) ? verse.text.indexOf(input) != -1    :
                ( type == 'prompt' ) ? verse.string.match(boundary_regex) :
                    verse.string.indexOf(input) != -1
            )
            .sort( ( a, b ) =>
                a.book    - b.book    ||
                a.chapter - b.chapter ||
                a.verse   - b.verse
            );
    }

    // given a verse reference, return the "next verse"
    next_verse( book, chapter, verse, bible = undefined ) {
        bible ||= this.bible();

        let found_verse = this.verses_by_bible[bible].find( this_verse =>
            this_verse.book    == book    &&
            this_verse.chapter == chapter &&
            this_verse.verse   == verse + 1
        );

        if ( ! found_verse ) found_verse = this.verses_by_bible[bible].find( this_verse =>
            this_verse.book    == book        &&
            this_verse.chapter == chapter + 1 &&
            this_verse.verse   == 1
        );

        return found_verse;
    }

    // given a word, return the synonyms at or above a given verity
    synonyms_of_word( word, verity = min_verity_level ) {
        word = word.toLowerCase();
        let key = Object.keys( this.loaded_data.thesaurus ).find( key => key.toLowerCase() == word );
        if ( ! key ) return;

        let entry = this.loaded_data.thesaurus[key];
        if ( typeof entry === 'string' ) {
            key   = entry;
            entry = this.loaded_data.thesaurus[key];
        }

        entry
            .filter( block => block.type == 'pron.' || block.type == 'article' )
            .forEach( block => block.synonyms = [] );

        entry.forEach( block =>
            block.synonyms = block.synonyms.filter( verity_level => verity_level.verity <= verity )
        );

        return { word: key, meanings: entry };
    }

    // given a verse reference, return the synonyms at or above a given verity
    synonyms_of_verse( book, chapter, verse, bible = undefined, verity = min_verity_level ) {
        bible ||= this.bible();

        return [ ...new Set(
            this.all_verses.find( this_verse =>
                this_verse.bible   == bible   &&
                this_verse.book    == book    &&
                this_verse.chapter == chapter &&
                this_verse.verse   == verse
            ).string.split(/\s/)
        ) ]
            .map( word => this.synonyms_of_word( word, verity ) )
            .filter( set => set );
    }

    // given a bible and verse object, return a multibible set of verses (with the origin verse first)
    multibible_verses(verse_object) {
        const other_bibles = this.loaded_data.bibles.filter( bible => bible != verse_object.bible );
        let other_verses   = [];

        if (other_bibles) {
            other_verses = other_bibles.map( other_bible => {
                const other_verse = this.lookup(
                    other_bible,
                    verse_object.book,
                    verse_object.chapter,
                    verse_object.verse,
                )[0];

                return {
                    bible: other_bible,
                    text : other_verse.text,
                    words: other_verse.string.split(/\s+/),
                };
            } );
        }

        return [
            {
                bible: verse_object.bible,
                text : verse_object.text,
                words: verse_object.words,
            },
            ...other_verses,
        ];
    }
}
