import Queries from 'classes/queries';
import distribution from 'modules/distribution';
import score from 'modules/scoring';
import {
    timeouts_per_team,
    max_appeals_declined_per_team,
    distribution_query_types,
    quizzer_response_duration,
    timeout_duration
} from 'modules/constants';

const json_quiz_path = '../../json/quizzes';

export default class Quiz {
    constructor (input) {
        if ( ! (
            typeof input.quiz     == 'string' ||
            typeof input.queries  == 'object' ||
            typeof input.material == 'string'
        ) ) throw 'Must instaniate Quiz with either a "quiz" name, a "queries" object, or a "material" label';

        this.ready =
            (
                ( input.quiz )
                    ? fetch( new URL( json_quiz_path + '/' + input.quiz + '.json', import.meta.url ) )
                        .then( reply => reply.json() )
                        .then( loaded_data => this.loaded_data = loaded_data )
                    : new Promise( (resolve) => {
                        this.loaded_data = {};
                        if ( input.events ) this.loaded_data.events = input.events;
                        if ( input.teams  ) this.loaded_data.teams  = input.teams ||
                            [
                                [ 'Team 1', [ 'Alpha Bravo',   'Charlie Delta', 'Echo Foxtrot' ] ],
                                [ 'Team 2', [ 'Gulf Hotel',    'India Juliet',  'Kilo Lima'    ] ],
                                [ 'Team 3', [ 'Mike November', 'Oscar Papa',    'Quebec Romeo' ] ],
                            ];
                        resolve();
                    } )
            )
            .then( () => {
                this.queries = ( input.queries ) ? input.queries : new Queries({
                    material            : this.loaded_data.material            || input.material,
                    min_verity_level    : this.loaded_data.min_verity_level    || input.min_verity_level,
                    references_selected : this.loaded_data.references_selected || input.references_selected,
                    prompts_selected    : this.loaded_data.prompts_selected    || input.prompts_selected,
                    settings            : this.loaded_data.query_settings      || input.query_settings,
                    history             : this.loaded_data.query_history       || input.query_history,
                });

                this.teams              = this.loaded_data.teams;
                this.events             = this.loaded_data.events;
                this.quiz_queries_cache = this.loaded_data.quiz_queries_cache || [];
                this.aux_queries_cache  = this.loaded_data.aux_queries_cache  || [];

                this.quizzer_response_duration =
                    this.loaded_data.quizzer_response_duration ||
                    input.quizzer_response_duration ||
                    quizzer_response_duration;

                this.timeout_duration = this.loaded_data.timeout_duration ||
                    input.timeout_duration ||
                    timeout_duration;

                let id_counter = 0;
                this.teams.forEach( ( team, i, teams ) => {
                    if ( Object.prototype.toString.call(team) === '[object Array]' ) team = {
                        name     : team[0],
                        quizzers : team[1],
                    };

                    team.timeouts_remaining = timeouts_per_team;
                    team.appeals_declined   = 0;

                    if ( ! team.id ) team.id = '_' + id_counter++;

                    team.quizzers.forEach( ( quizzer, j, quizzers ) => {
                        if ( typeof quizzer == 'string' ) quizzer = { name: quizzer };
                        if ( ! quizzer.id ) quizzer.id = '_' + id_counter++;
                        quizzers[j] = quizzer;
                    } );

                    teams[i] = team;
                } );

                return this.queries.ready.then( () => {
                    this.events ||= distribution(
                        this.queries.material.bibles_sequence,
                        this.teams.length,
                    );

                    this.quiz_queries_cache.push({
                        id    : 1,
                        query : this.queries.create(
                            this.events[0].type,
                            this.events[0].bible,
                        ),
                    });

                    score(this);
                    this.setup_prime_query();

                    this.preloaded = new Promise( (resolve) => {
                        let quiz_queries_cache_indexes = [ ...Array( this.events.length * 3 ) ]
                            .map( ( _, index ) => index % this.events.length );
                        quiz_queries_cache_indexes.shift();

                        let aux_queries_cache_definitions = distribution_query_types.flatMap( type =>
                            this.queries.material.bibles_sequence.map( bible => [ type, bible ] )
                        );

                        const populate_cache = () => {
                            console.log(
                                quiz_queries_cache_indexes.length +
                                aux_queries_cache_definitions.length
                            );

                            if ( quiz_queries_cache_indexes.length > 0 ) {
                                const index = quiz_queries_cache_indexes.shift();
                                console.log( this.events[index].type );

                                this.quiz_queries_cache.push({
                                    id    : index + 1,
                                    query : this.queries.create(
                                        this.events[index].type,
                                        this.events[index].bible,
                                    ),
                                });

                                setTimeout(populate_cache);
                            }
                            else if ( aux_queries_cache_definitions.length > 0 ) {
                                const definition = aux_queries_cache_definitions.shift();
                                console.log( definition[0] );

                                this.aux_queries_cache.push( this.queries.create(...definition) );
                                setTimeout(populate_cache);
                            }
                            else {
                                resolve(this);
                            }
                        }

                        setTimeout(populate_cache);
                    } );

                    return this;
                } );
            } );
    }

    data () {
        const queries_data = this.queries.data();
        return structuredClone({
            material                  : queries_data.material,
            min_verity_level          : queries_data.settings.min_verity_level,
            references_selected       : queries_data.references_selected,
            prompts_selected          : queries_data.prompts_selected,
            query_settings            : queries_data.settings,
            query_history             : queries_data.history,
            teams                     : this.teams,
            events                    : this.events,
            quiz_queries_cache        : this.quiz_queries_cache,
            aux_queries_cache         : this.aux_queries_cache,
            quizzer_response_duration : this.quizzer_response_duration,
            timeout_duration          : this.timeout_duration,
        });
    }

    // a "prime" query is a query that doesn't follow an incorrect (or when there are no teams eligible)
    setup_prime_query () {
        let index = this.events.findIndex( event => event.id && ! event.query );
        if ( index < 0 ) {
            const team_scores = this.teams.map( team => team.score.points );
            if ( ( new Set(team_scores) ).size === team_scores.length ) {
                this.events.forEach( event => delete event.current );
                console.log('Quiz Done');
                return;
            }

            const aux_query = this.aux_queries_cache.splice(
                Math.floor( Math.random() * this.aux_queries_cache.length ),
                1,
            )[0];

            this.events.push({
                id    : parseInt( this.events[ this.events.length - 1 ].id ) + 1,
                type  : aux_query.type,
                bible : aux_query.bible,
                query : aux_query,
            });
            index = this.events.length - 1;

            setTimeout( () =>
                this.aux_queries_cache.push( this.queries.create( aux_query.type, aux_query.bible ) )
            );
        }

        const next_query = this.events[index];
        next_query.id += 'A';
        next_query.query ||= this.#yank_cached_query(next_query);
        this.mark_current_query_event();
    }

    #yank_cached_query( target_query = undefined, type = undefined, bible = undefined ) {
        let query;

        if (target_query) {
            const queries = this.quiz_queries_cache.splice(
                this.quiz_queries_cache.findIndex( query => query.id == parseInt( target_query.id ) ),
                1,
            );
            if ( queries && queries.length > 0 ) query = queries[0].query;
        }

        type  ||= distribution_query_types[ Math.floor( Math.random() * distribution_query_types.length ) ];
        bible ||= this.queries.material.bibles_sequence[
            Math.floor( Math.random() * this.queries.material.bibles_sequence.length )
        ];

        if ( ! query ) {
            const queries = this.aux_queries_cache.splice(
                this.aux_queries_cache.findIndex( query => query.type == type && query.bible == bible ),
                1,
            );

            query = ( queries && queries.length > 0 )
                ? queries[0].query
                : this.queries.create( type, bible );

            setTimeout( () =>
                this.aux_queries_cache.push( this.queries.create( type, bible ) )
            );
        }

        return query;
    }

    current_query_event () {
        let index = this.events.findIndex( event => event.query && ! event.action );
        if ( index < 0 ) index = this.events.length - 1;
        return this.events[index];
    }

    mark_current_query_event() {
        this.events.forEach( event => delete event.current );
        this.current_query_event().current = true;
    }

    replace_query () {
        const current_query_event = this.current_query_event();
        this.#yank_cached_query( undefined, current_query_event.type, current_query_event.bible );
    }

    delete_last_action () {
        const last_action_event_index = this.events.findLastIndex( event => event.action );
        if ( typeof last_action_event_index === 'undefined' ) return;

        const current_query_event_index = this.events.findIndex( event => event.query && ! event.action );

        if ( last_action_event_index + 1 == current_query_event_index ) {
            const current_query_event = this.events[current_query_event_index];
            current_query_event.id = parseInt( current_query_event.id );

            this.quiz_queries_cache.unshift({
                id    : current_query_event.id,
                query : current_query_event.query,
            });

            delete current_query_event.query;
        }

        const last_action_event = this.events[last_action_event_index];

        if ( last_action_event.type ) last_action_event.type = last_action_event.type.substr( 0, 1 );

        delete last_action_event.action;
        delete last_action_event.team;
        delete last_action_event.quizzer;

        this.mark_current_query_event();
        score(this);
    }

    static #actions = [
        'no_trigger', 'correct', 'incorrect',
        'foul', 'timeout', 'appeal_accepted', 'appeal_declined',
    ];

    // process an action (handle the result/event of a query)
    action ( action, team_id = undefined, quizzer_id = undefined ) {
        action = Quiz.#actions.find( canonical_action => canonical_action == action.toLowerCase() );
        if ( ! action ) throw '"' + action + '" is not a valid action';

        const current_query_event = this.current_query_event();
        this[ 'action_' + action ]( current_query_event, action, team_id, quizzer_id );
    }

    action_no_trigger( current_query_event, action ) {
        current_query_event.action = action;
        this.setup_prime_query();
    }

    #ruling( current_query_event, action, team_id, quizzer_id ) {
        current_query_event.action  = action;
        current_query_event.team    = team_id;
        current_query_event.quizzer = quizzer_id;

        if (
            current_query_event.type.indexOf('X') == -1 &&
            current_query_event.type.indexOf('S') == -1 &&
            current_query_event.type.indexOf('V') == -1 &&
            current_query_event.type.indexOf('O') == -1
        ) current_query_event.type += 'S';

        score(this);
    }

    action_correct( current_query_event, action, team_id, quizzer_id ) {
        this.#ruling( current_query_event, action, team_id, quizzer_id );
        this.setup_prime_query();
    }

    action_incorrect( current_query_event, action, team_id, quizzer_id ) {
        this.#ruling( current_query_event, action, team_id, quizzer_id );

        const current_query_event_id_code =
            current_query_event.id.charCodeAt( current_query_event.id.length - 1 );

        if ( 64 + this.teams.length > current_query_event_id_code ) {
            this.events.splice( this.events.findIndex( event => event.current ) + 1, 0, {
                id :
                    parseInt( current_query_event.id ) +
                    String.fromCharCode( current_query_event_id_code + 1 ),
                bible : current_query_event.bible,
                type  : current_query_event.type.substr( 0, 1 ),
                query : this.#yank_cached_query(current_query_event),
            } );

            this.mark_current_query_event();
        }
        else {
            this.setup_prime_query();
        }
    }

    action_foul( current_query_event, action, team_id, quizzer_id ) {
        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action  : action,
            team    : team_id,
            quizzer : quizzer_id,

            quizzer_label : 'F',
        } );
    }

    action_timeout( current_query_event, action, team_id ) {
        const team = this.teams.find( (team) => team.id == team_id );
        team.timeouts_remaining--;

        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action : action,
            team   : team_id,

            team_label : 'T',
        } );
    }

    action_appeal_accepted( current_query_event, action, team_id ) {
        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action : action,
            team   : team_id,

            team_label : 'A+',
        } );
    }

    action_appeal_declined( current_query_event, action, team_id ) {
        const team = this.teams.find( (team) => team.id == team_id );
        team.appeals_declined++;

        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action : action,
            team   : team_id,

            team_label : 'A-',
        } );
    }
}
