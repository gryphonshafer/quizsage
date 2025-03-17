import Material from 'classes/material';

export default class Queries {
    static default_settings = {
        phrase_minimum_prompt_length           : 7,
        phrase_minimum_reply_length            : 1,
        chapter_reference_minimum_prompt_length: { key: 3, additional: 4 },
        chapter_reference_minimum_reply_length : 1,
        finish_prompt_length                   : 5,
        finish_minimum_reply_length            : 1,
    };

    constructor ( inputs = { queries : {} } ) {
        if ( inputs.queries === undefined ) inputs.queries = {};

        Object.keys( this.constructor.default_settings ).forEach( key =>
            this[key] = ( inputs.queries[key] !== undefined )
                ? inputs.queries[key]
                : this.constructor.default_settings[key]
        );

        this.references_selected = inputs.queries.references_selected || [];

        this.material = new Material(inputs);
        this.ready    = this.material.ready;
    }

    reset() {
        this.references_selected = [];
    }

    save() {
        const data = {
            references_selected: this.references_selected,
        };

        Object.keys(data).forEach( key => {
            if ( ! data[key].length ) delete data[key];
        } );

        return data;
    }

    static types = {
        p: { method: 'phrase', label: 'Phrase',            fresh_bible: true  },
        c: { method: 'cr',     label: 'Chapter Reference', fresh_bible: true  },
        q: { method: 'quote',  label: 'Quote',             fresh_bible: false },
        f: { method: 'finish', label: 'Finish',            fresh_bible: true  },
    };

    create( type, bible = undefined ) {
        const target_type = this.constructor.types[ type.toLowerCase().substr( 0, 1 ) ];
        if ( ! target_type ) throw '"' + type + '" is not a valid query type';
        bible ||= ( target_type.fresh_bible ) ? this.material.next_bible() : this.material.current_bible();
        return this[ 'create_' + target_type.method ](bible);
    }

    create_phrase(bible) {
        return this.#prep_return_data( this.#find_phrase_block(
            bible,
            'phrase',
            this.phrase_minimum_prompt_length,
            this.phrase_minimum_reply_length,
        ) );
    }

    create_cr(bible) {
        const block = this.#prep_return_data( this.#find_phrase_block(
            bible,
            'cr',
            this.chapter_reference_minimum_prompt_length,
            this.chapter_reference_minimum_reply_length,
        ) );
        block.pre_prompt = `From ${ block.book }, chapter ${ block.chapter }: `;
        return block;
    }

    create_quote(bible) {
        const verse = this.#select_verse(bible);
        const block = this.#prep_return_data({
            type      : 'Q',
            reply     : verse.text,
            full_reply: verse.text,
            verse     : verse,
        });
        block.pre_prompt = `Quote ${verse.book}, chapter ${verse.chapter}, verse ${verse.verse}.`;
        return block;
    }

    create_finish(bible) {
        let verse;
        let verse_find_attempts = 0;

        while (true) {
            verse_find_attempts++;
            verse = { words : [] };

            while (
                verse.words.length <
                this.finish_prompt_length + this.finish_minimum_reply_length
            ) verse = this.#select_verse(bible);

            const check_prompt  = verse.words.slice( 0, this.finish_prompt_length ).join(' ');
            const check_matches = this.material.verses_by_bible[bible].filter( check_verse =>
                check_verse.words.slice( 0, this.finish_prompt_length ).join(' ') == check_prompt
            );

            if ( check_matches.length == 1 ) break;
            if ( verse_find_attempts > 100 ) this.reset();
        }

        const [ prompt, reply, full_reply, prompt_words ] =
            this.#prompt_reply_text( verse, 0, this.finish_prompt_length );

        return this.#prep_return_data({
            type      : 'F',
            prompt    : prompt,
            reply     : reply,
            full_reply: full_reply,
            verse     : verse,
        });
    }

    #select_verse( bible, refs_filter = [] ) {
        let verses;
        let attempts = 0;

        while (true) {
            attempts++;
            if ( attempts > 2 ) throw 'Unable to select a verse from which to construct query';

            verses = this.material.verses(bible).filter( verse =>
                ! [ ...this.references_selected, ...refs_filter ].find(
                    reference => reference == verse.reference
                )
            );

            if ( verses.length > 0 ) break;
            this.reset();
        }

        return JSON.parse( JSON.stringify( verses[ Math.floor( Math.random() * verses.length ) ] ) );
    }

    #prompt_reply_text( verse, phrase_start, phrase_length, next_break = undefined ) {
        const prompt_words = verse.words.slice( phrase_start, phrase_start + phrase_length );

        const match = verse.text.match(
            new RegExp( '(\\b' + prompt_words.join('\\W+') + '\\b)\\W*(.+)', 'i' )
        );

        const prompt     = match[1] + '...';
        const full_reply = '...' + match[2];
        const reply      = (next_break)
            ? '...' + match[2].match(
                new RegExp(
                    '(\\b' + verse.words.slice(
                        phrase_start + phrase_length, next_break
                    ).join('\\W+') + '\\b\\S*)',
                    'i',
                )
            )[1]
            : full_reply;

        return [ prompt, reply, full_reply, prompt_words ];
    }

    #find_phrase_block( bible, type, min_prompt, min_reply ) {
        let refs_filter = [];

        const phrase_suffix_length    = ( typeof min_prompt === 'object' ) ? min_prompt.additional : 0;
        const min_prompt_total_length = ( typeof min_prompt === 'object' )
            ? Object.values(min_prompt).reduce( ( a, b ) => a + b, 0 )
            : min_prompt;

        let reset_count = 0;
        let attempts    = 0;

        while (true) {
            let verse;
            let phrase_start;

            while ( ! verse ) {
                attempts++;
                if ( attempts > 100 ) throw 'Unable to find phrase block from which to construct query';

                let verse_candidate;

                try {
                    verse_candidate = this.#select_verse( bible, refs_filter );
                }
                catch (e) {
                    // if #select_verse can't select a verse, then clear
                    // selected references, prompts, and filters and try again
                    // but increment reset count so we'll stop after 3 resets

                    reset_count++;

                    refs_filter = [];
                    this.reset();

                    verse_candidate = this.#select_verse( bible, refs_filter );
                }

                if ( reset_count >= 3 )
                    throw 'Unable to find phrase block from which to construct query';

                refs_filter.push( verse_candidate.reference );

                let offset = 0;
                while ( ! verse ) {
                    let phrase_length = min_prompt_total_length;
                    phrase_start      =
                        verse_candidate.words.length - phrase_length - min_reply - offset;

                    if ( phrase_start < 0 ) break;

                    while ( ! verse && phrase_start >= 0 ) {
                        const prompt_words = verse_candidate.words
                            .slice( phrase_start, phrase_start + phrase_length - phrase_suffix_length )
                            .join(' ');

                        const verses_with_phrase =
                            this.material.search( prompt_words, verse_candidate.bible, 'prompt' );

                        if (
                            type == 'phrase' && verses_with_phrase.length == 1 ||
                            type == 'cr' &&
                            verses_with_phrase
                                .filter(
                                    this_verse =>
                                        verse_candidate.book    == this_verse.book &&
                                        verse_candidate.chapter == this_verse.chapter
                                )
                                .length == 1 &&
                            verses_with_phrase
                                .filter(
                                    this_verse =>
                                        verse_candidate.book    != this_verse.book ||
                                        verse_candidate.chapter != this_verse.chapter
                                )
                                .length > 0
                        ) {
                            verse = verse_candidate;
                        }
                        else {
                            phrase_length++;
                            phrase_start--;
                        }
                    }

                    offset++;
                }
            }

            const phrase_starts = [ ...Array( phrase_start + 1 ).keys() ]
                .map( value => ({ value, sort: Math.random() }) )
                .sort( ( a, b ) => a.sort - b.sort )
                .map( ({value}) => value );

            for ( let i = 0; i < phrase_starts.length; i++ ) {
                const phrase_start     = phrase_starts[i];
                let phrase_length      = min_prompt_total_length;
                let verses_with_phrase = [];
                let prompt_words       = [];

                while ( phrase_start + phrase_length + min_reply < verse.words.length ) {
                    prompt_words = verse.words
                        .slice( phrase_start, phrase_start + phrase_length - phrase_suffix_length ).join(' ');

                    verses_with_phrase = this.material.search( prompt_words, verse.bible, 'prompt' );

                    if (
                        type == 'phrase' && verses_with_phrase.length == 1 ||
                        type == 'cr' &&
                        verses_with_phrase
                            .filter(
                                this_verse =>
                                    verse.book    == this_verse.book &&
                                    verse.chapter == this_verse.chapter
                            )
                            .length == 1 &&
                        verses_with_phrase
                            .filter(
                                this_verse =>
                                    verse.book    != this_verse.book ||
                                    verse.chapter != this_verse.chapter
                            )
                            .length > 0
                    ) break;

                    phrase_length++;
                }

                if ( phrase_start + phrase_length + min_reply >= verse.words.length ) continue;

                let next_break;
                if ( type == 'phrase' || type == 'cr' ) {
                    next_break = verse.breaks.find( this_break => phrase_start + phrase_length < this_break );
                    if ( next_break && phrase_start + phrase_length + min_reply > next_break ) continue;
                }

                if ( phrase_suffix_length > 0 )
                    prompt_words = verse.words.slice( phrase_start, phrase_start + phrase_length ).join(' ');

                if ( [ ...verse.string.matchAll( '\\b' + prompt_words + '\\b' ) ].length == 1 ) {
                    const [ prompt, reply, full_reply, prompt_words ] =
                        this.#prompt_reply_text( verse, phrase_start, phrase_length, next_break );

                    return {
                        type      : type,
                        prompt    : prompt,
                        reply     : reply,
                        full_reply: full_reply,
                        verse     : verse,
                    };
                }
            }
        }
    }

    #prep_return_data(block) {
        const type = block.type.toUpperCase().substr( 0, 1 );

        let return_data = {
            type     : type,
            type_name: this.constructor.types[ type.toLowerCase().substr( 0, 1 ) ].label,
            prompt   : block.prompt,
        };

        this.references_selected.push( block.verse.reference );

        return_data = {
            ...return_data,
            reply     : block.reply,
            full_reply: block.full_reply,
            bible     : block.verse.bible,
            book      : block.verse.book,
            chapter   : block.verse.chapter,
            verse     : block.verse.verse,
        };

        return JSON.parse( JSON.stringify(return_data) );
    }

    add_verse(query) {
        const next_verse = this.material.next_verse(
            query.book,
            query.chapter,
            query.verse,
            query.bible,
        );

        if ( ! next_verse ) throw 'Unable to find next verse';

        query.original = JSON.parse( JSON.stringify(query) );

        if ( query.type.substr( 0, 1 ).toUpperCase() == 'Q' )
            query.pre_prompt = `Quote ${query.book}, chapter ${query.chapter}, ` + (
                ( query.chapter == next_verse.chapter )
                    ? `verses ${query.verse} and ${next_verse.verse}.`
                    : `verse ${query.verse} and chapter ${next_verse.chapter}, verse ${next_verse.verse}.`
            );

        query.reply = query.full_reply + ' ' + next_verse.text;
        query.verse += '+' + (
            ( query.chapter == next_verse.chapter )
                ? next_verse.verse
                : next_verse.chapter + ':' + next_verse.verse
            );

        return query;
    }

    remove_verse(query) {
        if ( ! query.original ) throw 'Unable to remove verse';

        for ( let key in query ) {
            if ( key != 'original' ) query[key] = query.original[key];
        }

        delete query.original;

        return query;
    }
}
