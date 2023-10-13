const json_material_path = '../../json/material';

export default class Material {
    static settings = {
        material_json : undefined,
        minimum_verity: 3,
    };

    constructor ( input = {} ) {
        Object.keys( this.constructor.settings ).forEach( key =>
            this[key] = ( input[key] !== undefined ) ? input[key] : this.constructor.settings[key]
        );

        if ( ! this.material_json ) throw 'Material JSON not defined';

        this.ready = fetch( new URL(
            json_material_path + '/' + this.material_json + '.json',
            import.meta.url,
        ) )
            .then( reply => reply.json() )
            .then( loaded_data => {
                this.loaded_data = loaded_data;

                Object.keys( this.loaded_data.bibles ).forEach( bible =>
                    Object.keys( this.loaded_data.bibles[bible].content ).forEach( reference => {
                        const ref_parts = reference.match(/^(.+)\s+(\d+):(\d+)$/);
                        const verse     = this.loaded_data.bibles[bible].content[reference];

                        verse.bible     = bible;
                        verse.reference = reference;
                        verse.book      = ref_parts[1];
                        verse.chapter   = parseInt( ref_parts[2] );
                        verse.verse     = parseInt( ref_parts[3] );
                        verse.words     = this.constructor.text2words( verse.text );
                        verse.string    = verse.words.join(' ');
                    } )
                );

                this.primary_bibles = Object.keys( this.loaded_data.bibles )
                    .filter( bible => this.loaded_data.bibles[bible].type == 'primary' );

                this.all_verses = Object.values( this.loaded_data.bibles )
                    .flatMap( bible => Object.values( bible.content ) );

                this.verses_by_bible = Object.fromEntries( Object.keys( this.loaded_data.bibles )
                    .map( bible => [ bible, Object.values( this.loaded_data.bibles[bible].content ) ] ) );

                return this;
            } );
    }

    data() {
        return {
            ...Object.fromEntries( Object.keys( this.constructor.settings ).map( key => [ key, this[key] ] ) ),
        };
    }

    // split a text string into pure lowercase words ()
    static text2words(text) {
        // remove single-quotes from around words/phrases
        // remove commas, colons, and dashes at end of lines
        // remove commas followed by single-quote
        // remove commas and colons except for "1,234" and "3:00"
        // remove all but "usable" characters
        // convert dashes between numbers into spaces
        // remove single-quote following a non-word character
        // remove single-quote following a word character prior to a non-word
        // convert double-dashes into spaces
        // compact multi-spaces
        // trim spacing
        // lower-case
        // split with spaces

        return text
            .replaceAll( /(^|\W)'(\w.*?)'(\W|$)/g, '$1$2$3' )
            .replaceAll( /[,:\-]+$/g, '' )
            .replaceAll( /,'/g, '' )
            .replaceAll( /[,:](?=\D)/g, '' )
            .replaceAll( /[^A-Za-z0-9'\-,:]/gi, ' ' )
            .replaceAll( /(\d)\-(\d)/g, '$1 $2' )
            .replaceAll( /(?<!\w)'/g, ' ' )
            .replaceAll( /(\w)'(?=\W|$)/g, '$1' )
            .replaceAll( /\-{2,}/g, ' ' )
            .replaceAll( /\s+/g, ' ' )
            .replaceAll( /(?:^\s|\s$)/g, '' )
            .toLowerCase()
            .split(/\s/);
    }

    // next bible in an object-level shuffled sequence
    next_bible() {
        this.primary_bibles.push( this.primary_bibles.shift() );
        return this.current_bible();
    }

    // current bible
    current_bible() {
        return this.primary_bibles[ this.primary_bibles.length - 1 ];
    }

    // verses from a random-by-weight range given a bible (or the next bible in sequence)
    verses( bible = this.next_bible() ) {
        bible = bible.toUpperCase();
        if ( this.loaded_data.bibles[bible] === undefined ) throw '"' + bible + '" is not a valid Bible';

        const weights = this.loaded_data.ranges
            .map( ( range, index ) => Array( range.weight ).fill(index) )
            .flatMap( value => value );

        return this.loaded_data.ranges[
            weights[ Math.floor( Math.random() * weights.length ) ]
        ].verses.map( reference => this.loaded_data.bibles[bible].content[reference] );
    }

    // verse(s) given a bible, book, chapter (and optionally verse number)
    lookup( bible, book, chapter, verse_number = undefined ) {
        return (verse_number)
            ? [ this.loaded_data.bibles[bible].content[ book + ' ' + chapter + ':' + verse_number ] ]
            : this.verses_by_bible[bible].filter( this_verse =>
                book    == this_verse.book    &&
                chapter == this_verse.chapter
            );
    }

    // search for verses given a substring
    //     type "inexact" = match lower-case words of input against verse.string
    //     type "exact"   = match input against verse.text
    //     type "prompt"  = match lower-case words of input against verse.string with boundary edges
    search( input, bible = undefined, type = 'inexact' ) {
        if ( type == 'inexact' ) input = this.constructor.text2words(input).join(' ').toLowerCase();
        const boundary_regex = ( type == 'prompt' ) ? new RegExp( '\\b' + input + '\\b' ) : null;

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
        bible ||= this.current_bible();

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
    synonyms_of_word(word) {
        word = word.toLowerCase();
        let key = Object.keys( this.loaded_data.thesaurus ).find( key => key.toLowerCase() == word );
        if ( ! key ) return;

        let entry = structuredClone( this.loaded_data.thesaurus[key] );
        if ( typeof entry === 'string' ) {
            key   = entry;
            entry = this.loaded_data.thesaurus[key];
        }

        entry
            .filter( block => block.type == 'pron.' || block.type == 'article' || block.type == 'prep.' )
            .forEach( block => block.synonyms = [] );

        entry.forEach( range =>
            range.synonyms = range.synonyms.filter( synonym => synonym.verity <= this.minimum_verity )
        );

        return { word: key, meanings: entry };
    }

    // given a verse reference, return the synonyms at or above a given verity
    synonyms_of_verse( book, chapter, verse, bible = undefined ) {
        bible ||= this.current_bible();

        return [ ...new Set(
            this.verses_by_bible[bible].find( this_verse =>
                this_verse.book    == book    &&
                this_verse.chapter == chapter &&
                this_verse.verse   == verse
            ).string.split(/\s/)
        ) ].map( word => this.synonyms_of_word(word) ).filter( set => set );
    }

    // given a verse object, return a multi-bible set of verses
    multibible_verses(verse_object) {
        let other_verses   = [];
        const other_bibles = Object.keys( this.loaded_data.bibles )
            .filter( bible => bible != verse_object.bible );

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
        ]
            .map( value => ( { value, sort: value.bible } ) )
            .sort( ( a, b ) => a.sort > b.sort )
            .map( ( {value} ) => value );
    }
}
