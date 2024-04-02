import distribution from 'modules/distribution';
import Queries      from 'classes/queries';

OCJS.out(
    distribution(
        Object.keys( Queries.types ).map( type => type.toUpperCase() ),
        OCJS.in.bibles,
        OCJS.in.teams_count,
    )
);
