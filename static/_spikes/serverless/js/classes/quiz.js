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
        ) ) throw 'Must instantiate Quiz with either "quiz" name, "queries" object, or "material" label';

        this.ready =
            (
                ( input.quiz )
                    ? fetch( new URL( json_quiz_path + '/' + input.quiz + '.json', import.meta.url ) )
                        .then( reply => reply.json() )
                        .then( loaded_data => this.loaded_data = loaded_data )
                    : new Promise( resolve => {
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
                    material           : this.loaded_data.material            || input.material,
                    min_verity_level   : this.loaded_data.min_verity_level    || input.min_verity_level,
                    references_selected: this.loaded_data.references_selected || input.references_selected,
                    prompts_selected   : this.loaded_data.prompts_selected    || input.prompts_selected,
                    settings           : this.loaded_data.query_settings      || input.query_settings,
                });

                this.teams  = this.loaded_data.teams;
                this.events = this.loaded_data.events;

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
                        name    : team[0],
                        quizzers: team[1],
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

                    score(this);
                    this.setup_next_query();

                    return this;
                } );
            } );
    }

    data() {
        const queries_data = this.queries.data();
        return structuredClone({
            material                 : queries_data.material,
            min_verity_level         : queries_data.settings.min_verity_level,
            references_selected      : queries_data.references_selected,
            prompts_selected         : queries_data.prompts_selected,
            query_settings           : queries_data.settings,
            teams                    : this.teams,
            events                   : this.events,
            quizzer_response_duration: this.quizzer_response_duration,
            timeout_duration         : this.timeout_duration,
        });
    }

    setup_next_query( event_id_letter = 'A' ) {
        this.events.forEach( event => delete event.current );

        const event = this.events.find( event => event.id && ! event.action );
        if ( ! event ) return;

        if ( ! event.query ) event.query = this.queries.create( event.type, event.bible );
        event.id += event_id_letter;

        event.current = true;
    }

    replace_query(type) {
        const event = this.events.find( event => event.current );
        event.query = this.queries.create( type || event.type, event.bible );
    }

    static #actions = [
        'no_trigger', 'correct', 'incorrect',
        'foul', 'timeout', 'appeal_accepted', 'appeal_declined',
    ];

    action( action, team_id = undefined, quizzer_id = undefined ) {
        action = Quiz.#actions.find( canonical_action => canonical_action == action.toLowerCase() );
        if ( ! action ) throw '"' + action + '" is not a valid action';
        this[ 'action_' + action ]( team_id, quizzer_id );
        score(this);
    }

    action_no_trigger() {
        this.events.find( event => event.current ).action = 'no_trigger';
        this.setup_next_query();
    }

    action_correct( team_id, quizzer_id ) {
        this.#ruling( 'correct', team_id, quizzer_id );
        this.setup_next_query();
    }

    action_incorrect( team_id, quizzer_id ) {
        this.#ruling( 'incorrect', team_id, quizzer_id );

        const event                = this.events.find( event => event.current );
        const event_id_letter_code = event.id.charCodeAt( event.id.length - 1 );

        if ( event_id_letter_code < 64 + this.teams.length ) {
            this.events.splice( this.events.findIndex( event => event.current ) + 1, 0, {
                id   : parseInt( event.id ),
                bible: event.bible,
                type : event.type.substr( 0, 1 ),
            } );
            this.setup_next_query( String.fromCharCode( event_id_letter_code + 1 ) );
        }
        else {
            this.setup_next_query();
        }
    }

    #ruling( action, team_id, quizzer_id ) {
        const event = this.events.find( event => event.current );

        event.action     = action;
        event.team_id    = team_id;
        event.quizzer_id = quizzer_id;

        if (
            event.type.indexOf('X') == -1 &&
            event.type.indexOf('S') == -1 &&
            event.type.indexOf('V') == -1 &&
            event.type.indexOf('O') == -1
        ) event.type += 'S';
    }

    action_foul( team_id, quizzer_id ) {
        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action       : 'foul',
            team_id      : team_id,
            quizzer_id   : quizzer_id,
            quizzer_label: 'F',
        } );
    }

    action_timeout(team_id) {
        const team = this.teams.find( team => team.id == team_id );
        team.timeouts_remaining--;

        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action    : 'timeout',
            team_id   : team_id,
            team_label: 'T',
        } );
    }

    action_appeal_accepted(team_id) {
        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action    : 'appeal_accepted',
            team_id   : team_id,
            team_label: 'A+',
        } );
    }

    action_appeal_declined(team_id) {
        const team = this.teams.find( team => team.id == team_id );
        team.appeals_declined++;

        this.events.splice( this.events.findIndex( event => event.current ), 0, {
            action    : 'appeal_declined',
            team_id   : team_id,
            team_label: 'A-',
        } );
    }

    delete_last_action() {
        const last_action_event_index = this.events.findLastIndex( event => event.action );
        const last_action_event       = this.events[last_action_event_index];

        if (
            last_action_event.action == 'no_trigger' ||
            last_action_event.action == 'correct'    ||
            last_action_event.action == 'incorrect'
        ) {
            delete last_action_event.action;
            delete last_action_event.team_id;
            delete last_action_event.quizzer_id;
            delete last_action_event.team_label;
            delete last_action_event.quizzer_label;

            const current_event = this.events.find( event => event.current );

            current_event.id   = current_event.id  .substr( 0, 1 );
            current_event.type = current_event.type.substr( 0, 1 );

            delete current_event.current;
            last_action_event.current = true;
        }
        else {
            this.events.splice( last_action_event_index, 1 );
        }

        score(this);
    }
}
