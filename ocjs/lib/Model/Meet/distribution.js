import distribution from 'modules/distribution';
import Queries      from 'classes/queries';

console.log(
    distribution(
        Object.keys( Queries.types ).map( type => type.toUpperCase() ),
        window.bibles,
        window.teams_count,
    )
);
