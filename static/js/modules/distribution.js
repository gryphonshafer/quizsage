export default function ( query_types, bibles, teams_count ) {
    query_types = Object.fromEntries(
        Object.entries(
            JSON.parse( JSON.stringify(query_types) )
        ).map( ( [ key, value ] ) => [ key.toUpperCase(), value ] )
    );

    bibles = JSON.parse( JSON.stringify(bibles) )
        .map( bible => bible.toUpperCase() )
        .map( value => ( { value, sort: Math.random() } ) )
        .sort( ( a, b ) => a.sort - b.sort )
        .map( ( {value} ) => value );

    const query_type_letters = Object.keys(query_types);

    return [ ...Array( teams_count * 4 ) ]
        .map( ( _, index ) => query_type_letters[ index % query_type_letters.length ] )
        .map( value => ( { value, sort: Math.random() } ) )
        .sort( ( a, b ) => a.sort - b.sort )
        .map( ({value}) => value )
        .map(
            ( value, index ) => {
                const distribution_element = {
                    id  : index + 1,
                    type: value,
                };

                if ( query_types[value].fresh_bible ) {
                    bibles.push( bibles.shift() );
                    distribution_element.bible = bibles[0];
                }

                return distribution_element;
            }
        );
}
