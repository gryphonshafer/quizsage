import Material from 'classes/material';
const material = new Material( { material: { data: OCJS.in.material_data } } );

material.ready.then( () => {
    const refs_filter      = [];
    const verses_to_return = [];

    while (true) {
        if ( verses_to_return.length >= OCJS.in.count ) break;

        const bible  = material.next_bible();
        const verses = material.verses(bible).filter( verse =>
            ! refs_filter.find( reference => reference == verse.reference )
        );

        if ( verses.length == 0 ) {
            if ( material.verses(bible).length == 0 ) break;
            refs_filter.length = 0;
        }
        else {
            refs_filter.push( verses.reference );
            const picked_verse = verses[ Math.floor( Math.random() * verses.length ) ];
            verses_to_return.push({
                bible    : picked_verse.bible,
                book     : picked_verse.book,
                chapter  : picked_verse.chapter,
                verse    : picked_verse.verse,
                reference: picked_verse.reference,
                text     : picked_verse.text,
            });
        }
    }

    OCJS.out(verses_to_return);
} );
