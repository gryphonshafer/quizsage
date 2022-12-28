'use strict';
const QuizSageQueries = ( () => {
    function setup_settings( settings = {} ) {
        settings.phrase_min_prompt_length ||= 4;
        settings.phrase_min_reply_length  ||= 2;
        settings.cr_min_prompt_length     ||= 3;
        settings.cr_min_reply_length      ||= 2;
        settings.finish_prompt_length     ||= 5;
        settings.finish_min_reply_length  ||= 2;
        settings.xr_min_prompt_length     ||= 4;
        settings.xr_min_references        ||= 2;
        return settings;
    }

    function label2file(label) {
        let file = label;
        file = file.replace( / /g,  '_' );
        file = file.replace( /\(/g, '{' );
        file = file.replace( /\)/g, '}' );
        file = file.replace( /;/g,  '+' );
        file = file.replace( /:/g,  '%' );
        return '../../json/material/' + file + '.json';
    }

    return function ( input = {} ) {
        this.settings = setup_settings( input.settings );
        this.label    = input.label;
        this.file     = label2file( this.label );

        this.references_selected = input.references_selected || [];
        this.prompts_selected    = input.prompts_selected    || [];

        this.material;

        this.ready = fetch( this.file )
            .then( reply => reply.json() )
            .then( material => this.material = material )
            .then( () => this );

        this.create = ( type, bible ) => {
            const types = {
                p : 'phrase',
                c : 'cr',
                q : 'quote',
                f : 'finish',
                x : 'xr',
            };

            const method = types[ type.toLowerCase().substr( 0, 1 ) ];
            if ( ! method ) throw '"' + type + '" is not a valid query type';

            bible = bible.toUpperCase();
            if ( this.material.bibles.filter( item => item == bible ).length != 1 )
                throw '"' + bible + '" is not a valid Bible';

            return this[ 'create_' + method ](bible);
        }

        this.create_phrase = (bible) => {
            return _prep_return_data( _find_phrase_block(
                bible,
                'phrase',
                this.settings.phrase_min_prompt_length,
                this.settings.phrase_min_reply_length,
            ) );
        }

        this.create_cr = (bible) => {
            const block = _prep_return_data( _find_phrase_block(
                bible,
                'cr',
                this.settings.cr_min_prompt_length,
                this.settings.cr_min_reply_length,
            ) );
            block.prompt = `From ${ block.book }, chapter ${ block.chapter }: ${ block.prompt }`;
            return block;
        }

        this.create_quote = (bible) => {
            const verse = _select_verse(bible);

            return _prep_return_data({
                type   : 'Q',
                bible  : bible,
                prompt : `Quote ${verse.book}, chapter ${verse.chapter}, verse ${verse.verse}.`,
                reply  : verse.text,
                verse  : verse,
            });
        }

        this.create_finish = (bible) => {
            let verse = { words : [] };
            while (
                verse.words.length <
                this.settings.finish_prompt_length + this.settings.finish_min_reply_length
            ) verse = _select_verse(bible);

            const [ prompt, reply, prompt_words ] =
                _prompt_reply_text( verse, 0, this.settings.finish_prompt_length );

            return _prep_return_data({
                type   : 'F',
                bible  : bible,
                prompt : prompt,
                reply  : reply,
                verse  : verse,
            });
        }

        this.create_xr = (bible) => {
            return _prep_return_data( _find_phrase_block(
                bible,
                'xr',
                this.settings.xr_min_prompt_length,
                this.settings.xr_min_reply_length,
                this.settings.xr_min_references,
            ) );
        }

        this.reset = () => {
            this.references_selected = [];
            this.prompts_selected    = [];
        }

        this.data = () => {
            return {
                label               : this.label,
                settings            : this.settings,
                references_selected : this.references_selected,
                prompts_selected    : this.prompts_selected,
            };
        }

        const _select_verse = ( bible, type = 'not_xr', refs_filter = [] ) => {
            const weights = this.material.blocks
                .map( ( block, index ) => Array( block.weight ).fill(index) )
                .flatMap( value => value );

            let verses = this.material.blocks[
                weights[ Math.floor( Math.random() * weights.length ) ]
            ].content[bible];

            if ( type != 'xr' ) {
                verses = verses.filter( verse =>
                    ! [ ...this.references_selected, ...refs_filter ].find(
                        reference => reference == verse.book + ' ' + verse.chapter  + ':' + verse.verse
                    )
                );
            }
            else {
                verses = verses.filter( verse =>
                    ! this.prompts_selected.find(
                        prompt => verse.string.match( '\\b' + prompt.join('\\W+') + '\\b' )
                    ) &&
                    ! refs_filter.find(
                        reference => reference == verse.book + ' ' + verse.chapter  + ':' + verse.verse
                    )
                );
            }

            if ( verses.length == 0 ) throw 'Exhausted available verses';

            const verse     = verses[ Math.floor( Math.random() * verses.length ) ];
            verse.reference = verse.book + ' ' + verse.chapter  + ':' + verse.verse;
            verse.words     = verse.string.split(/\s+/);

            return verse;
        }

        const _prompt_reply_text = ( verse, phrase_start, phrase_length ) => {
            const prompt_words = verse.words.slice( phrase_start, phrase_start + phrase_length );

            const match = verse.text.match(
                new RegExp( '(\\b' + prompt_words.join('\\W+') + '\\b)\\W*(.+)', 'i' )
            );

            const prompt = match[1] + '...';
            const reply  = '...' + match[2];

            return [ prompt, reply, prompt_words ];
        }

        const _find_phrase_block = (
            bible,
            type           = 'phrase',
            min_prompt     = 4,
            min_reply      = 2,
            min_references = 2,
        ) => {
            const refs_filter = [];

            while (true) {
                let verse;
                let phrase_start;

                while ( ! verse ) {
                    const verse_candidate = _select_verse( bible, type, refs_filter );
                    refs_filter.push( verse_candidate.reference );

                    let offset = 0;
                    while ( ! verse ) {
                        let phrase_length = min_prompt;
                        phrase_start      =
                            verse_candidate.words.length - phrase_length - min_reply - offset;

                        if ( phrase_start < 0 ) break;

                        while ( ! verse && phrase_start >= 0 ) {
                            const prompt_words = verse_candidate.words
                                .slice( phrase_start, phrase_start + phrase_length ).join(' ');

                            const verses_with_phrase = this.material.blocks
                                .map( block => block.content[bible] )
                                .flatMap( value => value )
                                .filter(
                                    this_verse => this_verse.string.match( '\\b' + prompt_words + '\\b' )
                                );

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
                    let phrase_length      = min_prompt;
                    let verses_with_phrase = [];
                    let prompt_words       = [];

                    while ( phrase_start + phrase_length + min_reply < verse.words.length ) {
                        prompt_words = verse.words
                            .slice( phrase_start, phrase_start + phrase_length ).join(' ');

                        verses_with_phrase = this.material.blocks
                            .map( block => block.content[bible] )
                            .flatMap( value => value )
                            .filter(
                                this_verse => this_verse.string.match( '\\b' + prompt_words + '\\b' )
                            );

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

                    if ( type == 'xr' ) {
                        if ( verses_with_phrase.length >= min_references ) {
                            const [ prompt, reply, prompt_words ] =
                                _prompt_reply_text( verse, phrase_start, phrase_length );

                            return {
                                type         : type,
                                bible        : bible,
                                prompt       : prompt,
                                verses       : verses_with_phrase,
                                prompt_words : prompt_words,
                            };
                        }
                    }
                    else {
                        if ( [ ...verse.string.matchAll( '\\b' + prompt_words + '\\b' ) ].length == 1 ) {
                            const [ prompt, reply, prompt_words ] =
                                _prompt_reply_text( verse, phrase_start, phrase_length );

                            return {
                                type   : type,
                                bible  : bible,
                                prompt : prompt,
                                reply  : reply,
                                verse  : verse,
                            };
                        }
                    }
                }
            }
        }

        const _prep_return_data = (block) => {
            const type = block.type.toUpperCase().substr( 0, 1 );

            const type_names = {
                p : 'Phrase',
                c : 'Chapter Reference',
                q : 'Quote',
                f : 'Finish',
                x : 'Cross-Reference',
            };

            const return_data = {
                type      : type,
                type_name : type_names[ type.toLowerCase() ],
                bible     : block.bible,
                prompt    : block.prompt,
            };

            if ( type != 'X' ) {
                this.references_selected.push( block.verse.reference );

                const other_bibles = Object
                    .keys( this.material.blocks[0].content )
                    .filter( bible => bible != block.bible );

                let other_verses = [];

                if (other_bibles) {
                    other_verses = other_bibles.map( other_bible => {
                        const other_verse = this.material.blocks
                            .map( block => block.content[other_bible] )
                            .flat(2)
                            .find( verse =>
                                verse.book    == block.verse.book    &&
                                verse.chapter == block.verse.chapter &&
                                verse.verse   == block.verse.verse
                            );

                        return {
                            bible : other_bible,
                            text  : other_verse.text,
                            words : other_verse.string.split(/\s+/),
                        };
                    } );
                }

                const material = [
                    {
                        bible : block.bible,
                        text  : block.verse.text,
                        words : block.verse.words,
                    },
                    ...other_verses,
                ];

                material.forEach( (verse) => {
                    verse.thesaurus = {};
                    [ ...new Set( verse.words ) ].forEach( (word) => {
                        let entry = this.material.thesaurus[word];
                        if (entry) {
                            if ( typeof entry === 'string' ) entry = this.material.thesaurus[entry];

                            entry
                                .filter( (block) => block.type == 'pron.' || block.type == 'article' )
                                .forEach( (block) => block.synonyms = [] );

                            verse.thesaurus[word] = entry;
                        }
                    });
                } );

                return {
                    ...return_data,
                    reply    : block.reply,
                    book     : block.verse.book,
                    chapter  : block.verse.chapter,
                    verse    : block.verse.verse,
                    material : material,
                };
            }
            else {
                this.prompts_selected.push( block.prompt_words );

                return {
                    ...return_data,
                    references : block.verses.map(
                        verse => verse.book + ' ' + verse.chapter  + ':' + verse.verse
                    ),
                };
            }
        }
    }
} )();
