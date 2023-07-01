import Material from 'classes/material';

export default class Queries {
    static settings = {
        phrase_minimum_prompt_length           : 6,
        phrase_minimum_reply_length            : 2,
        chapter_reference_minimum_prompt_length: { key: 3, additional: 3 },
        chapter_reference_minimum_reply_length : 2,
        finish_prompt_length                   : 5,
        finish_minimum_reply_length            : 2,
        cross_reference_minimum_prompt_length  : 4,
        cross_reference_minimum_references     : 2,
    };

    constructor ( input = {} ) {
        Object.keys( this.constructor.settings ).forEach( key =>
            this[key] = ( input[key] !== undefined ) ? input[key] : this.constructor.settings[key]
        );

        this.references_selected = input.references_selected || [];
        this.prompts_selected    = input.prompts_selected    || [];
        this.material            = new Material(input);

        this.ready = this.material.ready.then( () => this );
    }

    data() {
        return {
            ...Object.fromEntries( Object.keys( this.constructor.settings ).map( key => [ key, this[key] ] ) ),
            ...this.material.data(),
            references_selected: this.references_selected,
            prompts_selected   : this.prompts_selected,
        };
    }

    reset() {
        this.references_selected = [];
        this.prompts_selected    = [];
    }

    static types = {
        p: { method: 'phrase', label: 'Phrase'            },
        c: { method: 'cr',     label: 'Chapter Reference' },
        q: { method: 'quote',  label: 'Quote'             },
        f: { method: 'finish', label: 'Finish'            },
        // x: { method: 'xr',     label: 'Cross-Reference'   },
    };

    create( type, bible = undefined ) {
        const target_type = this.constructor.types[ type.toLowerCase().substr( 0, 1 ) ];
        if ( ! target_type ) throw '"' + type + '" is not a valid query type';
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
        block.prompt = `From ${ block.book }, chapter ${ block.chapter }: ${ block.prompt }`;
        return block;
    }

    create_quote(bible) {
        const verse = this.#select_verse(bible);

        return this.#prep_return_data({
            type  : 'Q',
            prompt: `Quote ${verse.book}, chapter ${verse.chapter}, verse ${verse.verse}.`,
            reply : verse.text,
            verse : verse,
        });
    }

    create_finish(bible) {
        let verse = { words : [] };
        while (
            verse.words.length <
            this.finish_prompt_length + this.finish_minimum_reply_length
        ) verse = this.#select_verse(bible);

        const [ prompt, reply, prompt_words ] =
            this.#prompt_reply_text( verse, 0, this.finish_prompt_length );

        return this.#prep_return_data({
            type  : 'F',
            prompt: prompt,
            reply : reply,
            verse : verse,
        });
    }

    // create_xr(bible) {
    //     return this.#prep_return_data( this.#find_phrase_block(
    //         bible,
    //         'xr',
    //         this.cross_reference_minimum_prompt_length,
    //         this.cross_reference_minimum_references,
    //     ) );
    // }

    #select_verse( bible, type = 'not_xr', refs_filter = [] ) {
        const verses = this.material.verses(bible).filter( verse =>
            type != 'xr' &&
            ! [ ...this.references_selected, ...refs_filter ].find(
                reference => reference == verse.book + ' ' + verse.chapter  + ':' + verse.verse
            ) ||
            type == 'xr' &&
            ! this.prompts_selected.find(
                prompt => verse.string.match( '\\b' + prompt.join('\\W+') + '\\b' )
            ) &&
            ! refs_filter.find(
                reference => reference == verse.book + ' ' + verse.chapter  + ':' + verse.verse
            )
        );

        if ( verses.length == 0 ) throw 'Exhausted available verses';

        const verse     = structuredClone( verses[ Math.floor( Math.random() * verses.length ) ] );
        verse.reference = verse.book + ' ' + verse.chapter  + ':' + verse.verse;
        verse.words     = verse.string.split(/\s+/);
        verse.bible     = bible || this.material.bible();

        return verse;
    }

    #prompt_reply_text( verse, phrase_start, phrase_length ) {
        const prompt_words = verse.words.slice( phrase_start, phrase_start + phrase_length );

        const match = verse.text.match(
            new RegExp( '(\\b' + prompt_words.join('\\W+') + '\\b)\\W*(.+)', 'i' )
        );

        const prompt = match[1] + '...';
        const reply  = '...' + match[2];

        return [ prompt, reply, prompt_words ];
    }

    #find_phrase_block( bible, type, min_prompt, min_reply ) {
        let refs_filter = [];

        const phrase_suffix_length    = ( typeof min_prompt === 'object' ) ? min_prompt.additional : 0;
        const min_prompt_total_length = ( typeof min_prompt === 'object' )
            ? Object.values(min_prompt).reduce( ( a, b ) => a + b, 0 )
            : min_prompt;

        while (true) {
            let verse;
            let phrase_start;

            while ( ! verse ) {
                let verse_candidate;
                try {
                    verse_candidate = this.#select_verse( bible, type, refs_filter );
                }
                catch (e) {
                    // if #select_verse can't select a verse, then clear
                    // selected references, prompts, and filters and try again

                    refs_filter = [];
                    this.reset();

                    verse_candidate = this.#select_verse( bible, type, refs_filter );
                }
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
                            type == 'xr' && verses_with_phrase.length > 1 ||
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
                        type == 'xr' && verses_with_phrase.length > 1 ||
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

                if ( phrase_suffix_length > 0 )
                    prompt_words = verse.words.slice( phrase_start, phrase_start + phrase_length ).join(' ');

                if ( type != 'xr' ) {
                    if ( [ ...verse.string.matchAll( '\\b' + prompt_words + '\\b' ) ].length == 1 ) {
                        const [ prompt, reply, prompt_words ] =
                            this.#prompt_reply_text( verse, phrase_start, phrase_length );

                        return {
                            type  : type,
                            prompt: prompt,
                            reply : reply,
                            verse : verse,
                        };
                    }
                }
                else {
                    if ( verses_with_phrase.length >= min_reply ) {
                        const [ prompt, reply, prompt_words ] =
                            this.#prompt_reply_text( verse, phrase_start, phrase_length );

                        return {
                            type        : type,
                            prompt      : prompt,
                            verses      : verses_with_phrase,
                            prompt_words: prompt_words,
                        };
                    }
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

        if ( type != 'X' ) {
            this.references_selected.push( block.verse.reference );

            const material = this.material.multibible_verses( block.verse );

            material.forEach( verse =>
                verse.thesaurus = this.material.synonyms_of_verse(
                    block.verse.book,
                    block.verse.chapter,
                    block.verse.verse,
                    verse.bible,
                )
            );

            return_data = {
                ...return_data,
                reply   : block.reply,
                bible   : block.verse.bible,
                book    : block.verse.book,
                chapter : block.verse.chapter,
                verse   : block.verse.verse,
                material: material,
            };
        }
        else {
            this.prompts_selected.push( block.prompt_words );

            return_data = {
                ...return_data,
                bible     : block.verses[0].bible,
                references: block.verses.map(
                    verse => verse.book + ' ' + verse.chapter  + ':' + verse.verse
                ),
            };
        }

        return structuredClone(return_data);
    }

    add_verse(query) {
        const next_verse = this.material.next_verse(
            query.book,
            query.chapter,
            query.verse,
            query.bible,
        );

        if ( ! next_verse ) throw 'Unable to find next verse';

        query.original = structuredClone(query);

        if ( query.type.substr( 0, 1 ).toUpperCase() == 'Q' ) query.prompt =
            `Quote ${query.book}, chapter ${query.chapter}, verses ${query.verse} and ${next_verse.verse}.`;

        query.reply += ' ' + next_verse.text;
        query.verse += '-' + next_verse.verse;

        const added_material = this.material.multibible_verses(next_verse);

        added_material.forEach( verse =>
            verse.thesaurus = this.material.synonyms_of_verse(
                next_verse.book,
                next_verse.chapter,
                next_verse.verse,
                next_verse.bible,
            )
        );

        for ( let index = 0; index < query.material.length; ++index ) {
            query.material[index].text += ' ' + added_material[index].text;
            query.material[index].thesaurus.push( ...added_material[index].thesaurus );
        }

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
