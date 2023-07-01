// import {distribution_query_types} from 'modules/constants';

export default function ( query_types, bibles, teams_count ) {
    return [ ...Array( teams_count * 4 ) ]
        .map( ( _, index ) => query_types[ index % query_types.length ] )
        .map( value => ( { value, sort: Math.random() } ) )
        .sort( ( a, b ) => a.sort - b.sort )
        .map( ({value}) => value )
        .map(
            ( value, index ) => {
                return {
                    id   : index + 1,
                    type : value,
                    bible: bibles[ index % bibles.length ],
                };
            }
        );
}
