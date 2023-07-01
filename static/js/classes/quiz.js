import Queries from 'classes/queries';
import Scoring from 'classes/scoring';
import distribution from 'modules/distribution';

export default class Quiz {
    static settings = {
        quizzer_response_duration        : 40,
        timeout_duration                 : 40,
        timeouts_per_team                : 1,
        maximum_declined_appeals_per_team: 2,
    };

    constructor (input) {
        Object.keys( this.constructor.settings ).forEach( key =>
            this[key] = ( input[key] !== undefined ) ? input[key] : this.constructor.settings[key]
        );

        this.state = input.state || {};

        this.teams = input.teams || [
            [ 'Team 1', [ [ 'Alpha Bravo',   'NIV' ], [ 'Charlie Delta', 'NIV' ], [ 'Echo Foxtrot', 'NIV' ] ] ],
            [ 'Team 2', [ [ 'Gulf Hotel',    'ESV' ], [ 'India Juliet',  'ESV' ], [ 'Kilo Lima',    'ESV' ] ] ],
            [ 'Team 3', [ [ 'Mike November', 'NIV' ], [ 'Oscar Papa',    'NIV' ], [ 'Quebec Romeo', 'NIV' ] ] ],
        ];
        let id_counter = 0;
        this.teams.forEach( ( team, i, teams ) => {
            if ( Object.prototype.toString.call(team) === '[object Array]' ) team = {
                name    : team[0],
                quizzers: team[1],
            };

            team.timeouts_remaining = this.timeouts_per_team;
            team.appeals_declined   = 0;

            if ( ! team.id ) team.id = '_' + id_counter++;

            team.quizzers.forEach( ( quizzer, j, quizzers ) => {
                if ( typeof quizzer == 'string' ) quizzer = { name: quizzer };
                if ( Object.prototype.toString.call(quizzer) === '[object Array]' ) quizzer = {
                    name : quizzer[0],
                    bible: quizzer[1],
                };
                if ( ! quizzer.id ) quizzer.id = '_' + id_counter++;
                quizzers[j] = quizzer;
            } );

            teams[i] = team;
        } );

        this.scoring = new Scoring(input);
        this.queries = new Queries(input);

        this.ready = this.queries.ready.then( () => {
            this.distribution = input.distribution || distribution(
                Object.keys( this.queries.constructor.types ).map( type => type.toLocaleUpperCase() ),
                this.queries.material.bibles(),
                this.teams.length,
            );

            this.state.events ||= [];
            this.#build_board();

            return this;
        } );
    }

    data() {
        return {
            ...Object.fromEntries( Object.keys( this.constructor.settings ).map( key => [ key, this[key] ] ) ),
            ...this.scoring.data(),
            ...this.queries.data(),
            ...this.queries.material.data(),
            state       : this.state,
            teams       : this.teams,
            distribution: this.distribution,
        };
    }

    #build_board() {
        this.state.teams   ||= structuredClone( this.teams );
        this.state.queries ||= [];

        const distribution = structuredClone( this.distribution  );
        const queries      = structuredClone( this.state.queries );

        this.state.board = [];

        this.state.events.forEach( event => {
            const record = structuredClone(event);

            // if event is a ruled action...
            if (
                record.action == 'no_trigger' ||
                record.action == 'correct'    ||
                record.action == 'incorrect'
            ) {
                this.#setup_query( record, queries, distribution );

                if ( record.action == 'correct' || record.action == 'incorrect' )
                    record.type = record.type.toUpperCase() + record.qsstypes;
            }

            if ( record.action == 'foul' ) {
                record.quizzer_label = 'F';
            }
            else if ( record.action == 'timeout' ) {
                this.state.teams.find( team => team.id == record.team_id ).timeouts_remaining--;
                record.team_label = 'T';
            }
            else if ( record.action == 'appeal_accepted' ) {
                record.team_label = 'A+';
            }
            else if ( record.action == 'appeal_declined' ) {
                this.state.teams.find( team => team.id == record.team_id ).appeals_declined++;
                record.team_label = 'A-';
            }

            this.state.board.push(record);
        } );

        // setup next query if there's more of the quiz remaining
        if ( distribution.length ) {
            const record = { current: true };
            this.#setup_query( record, queries, distribution );
            this.state.board.push(record);
        }

        // append any remaining distribution
        while ( distribution.length ) {
            this.state.board.push( distribution.shift() );
        }

        this.scoring.score(this);
    }

    #setup_query( record, queries, distribution ) {
        const previous_ruling = this.state.board.findLast( existing_record =>
            existing_record.action == 'no_trigger' ||
            existing_record.action == 'correct'    ||
            existing_record.action == 'incorrect'
        );
        if ( previous_ruling && previous_ruling.action == 'incorrect' ) {
            const id_letter_code = previous_ruling.id.charCodeAt( previous_ruling.id.length - 1 );
            if ( id_letter_code < 64 + this.state.teams.length ) {
                record.type  = previous_ruling.type.substr( 0, 1 );
                record.bible = previous_ruling.bible;
                record.id    = parseInt( previous_ruling.id ) +
                    String.fromCharCode( id_letter_code + 1 );
            }
        }

        if ( ! record.id ) Object.assign( record, distribution.shift() );
        if ( record.id == parseInt( record.id ) ) record.id += 'A';

        // append a query to the record (try from cache first; otherwise create)
        const found_index = queries.findIndex( query =>
            record.type.substr( 0, 1 ) == record.type.substr( 0, 1 ) &&
            record.bible == record.bible
        );
        if ( found_index > -1 ) record.query = queries.splice( found_index, 1 ).shift();
        if ( ! record.query ) {
            record.query = this.queries.create( record.type.substr( 0, 1 ), record.bible );
            this.state.queries.push( record.query );
        }
    }

    static #actions = [
        'no_trigger', 'correct', 'incorrect',
        'foul', 'timeout', 'appeal_accepted', 'appeal_declined',
    ];

    action( action, team_id = undefined, quizzer_id = undefined, qsstypes = undefined ) {
        action = this.constructor.#actions.find(
            canonical_action => canonical_action == action.toLowerCase()
        );
        if ( ! action ) throw '"' + action + '" is not a valid action';

        const event = { action: action };

        if (team_id)    event.team_id    = team_id;
        if (quizzer_id) event.quizzer_id = quizzer_id;
        if (qsstypes) {
            qsstypes       = qsstypes.toUpperCase();
            event.qsstypes = '';

            if ( qsstypes.indexOf('V') != -1 ) {
                event.qsstypes += 'V';
            }
            else if ( qsstypes.indexOf('O') != -1 ) {
                event.qsstypes += 'O';
            }
            else {
                event.qsstypes += 'S';
            }

            if ( qsstypes.indexOf('R') != -1 ) event.qsstypes += 'R';
            if ( qsstypes.indexOf('A') != -1 ) event.qsstypes += 'A';
        }

        this.state.events.push(event);
        this.#build_board();
    }

    replace_query() {
        const record      = this.state.board.find( record => record.current );
        const query_index = this.state.queries.findIndex( query =>
            query.bible   == record.query.bible   &&
            query.book    == record.query.book    &&
            query.chapter == record.query.chapter &&
            query.verse   == record.query.verse   &&
            query.prompt  == record.query.prompt  &&
            query.type    == record.query.type
        );

        const new_query = this.queries.create( record.query.type, record.query.bible );

        this.state.queries[query_index] = new_query;
        record.query                    = new_query;
    }

    delete_last_action() {
        this.state.events.pop();
        this.#build_board();
    }
}
