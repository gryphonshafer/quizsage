import distribution from 'modules/distribution';
import Queries      from 'classes/queries';

OCJS.out(
    distribution(
        Queries.types,
        OCJS.in.bibles,
        OCJS.in.teams_count,
    )
);
