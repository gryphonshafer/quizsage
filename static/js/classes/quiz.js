import distribution from 'modules/distribution';
import Queries      from 'classes/queries';
import Scoring      from 'classes/scoring';

export default class Quiz {
    static default_settings = {
        quizzer_response_duration        : 40,
        timeout_duration                 : 40,
        appeal_duration                  : 180,
        timeouts_per_team                : 1,
        maximum_declined_appeals_per_team: 2,
    };

    constructor ( inputs = { quiz : {} } ) {
        if ( inputs.quiz === undefined ) inputs.quiz = {};

        Object.keys( this.constructor.default_settings ).forEach( key =>
            this[key] = ( inputs.quiz[key] !== undefined )
                ? inputs.quiz[key]
                : this.constructor.default_settings[key]
        );

        this.state = inputs.quiz.state || {};

        this.teams = this.state.teams || inputs.quiz.teams || [
            [ 'Team 1', [ [ 'Alpha Bravo',   'NIV' ], [ 'Charlie Delta', 'NIV' ], [ 'Echo Foxtrot', 'NIV' ] ] ],
            [ 'Team 2', [ [ 'Gulf Hotel',    'NIV' ], [ 'Juliet India',  'NIV' ], [ 'Kilo Lima',    'NIV' ] ] ],
            [ 'Team 3', [ [ 'Mike November', 'NIV' ], [ 'Oscar Papa',    'NIV' ], [ 'Romeo Quebec', 'NIV' ] ] ],
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

        this.scoring = new Scoring(inputs);

        inputs.queries = { ...inputs.queries, ...this.state.queries };
        this.queries   = new Queries(inputs);
        this.ready     = this.queries.ready;

        this.ready.then( () => {
            this.distribution = this.state.distribution || inputs.quiz.distribution || distribution(
                Object.keys( this.queries.constructor.types ).map( type => type.toUpperCase() ),
                this.queries.material.primary_bibles,
                this.teams.length,
            );

            this.state.events ||= [];

            try {
                this.#build_board();
            }
            catch (e) {
                this.error = e;
            }

            return this;
        } );
    }

    save() {
        const data = {
            ...this.state,
            distribution : this.distribution,
            queries      : this.queries.save(),
        };

        if ( ! Object.keys( data.queries ).length ) delete data.queries;

        return data;
    }

    #build_board() {
        const distribution       = JSON.parse( JSON.stringify( this.distribution ) );
        this.state.teams       ||= JSON.parse( JSON.stringify( this.teams ) );
        this.state.board       ||= [];
        this.state.query_cache ||= [];

        this.state.query_cache.unshift( ...this.state.board.map( row => row.query ).filter( query => query ) );
        this.state.board = [];

        this.state.events.forEach( event => {
            const record = JSON.parse( JSON.stringify(event) );

            // if event is a ruled action...
            if (
                record.action == 'no_trigger' ||
                record.action == 'correct'    ||
                record.action == 'incorrect'
            ) {
                this.#setup_query( record, distribution );

                if ( record.action == 'correct' || record.action == 'incorrect' )
                    record.type = record.type.toUpperCase() + record.qsstypes;
            }
            else if ( record.action == 'foul' ) {
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

        let append_final_query = false;
        if ( distribution.length == 0 ) {
            const previous_ruling = this.state.board.findLast( existing_record =>
                existing_record.action == 'no_trigger' ||
                existing_record.action == 'correct'    ||
                existing_record.action == 'incorrect'
            );
            if ( previous_ruling && previous_ruling.action == 'incorrect' ) {
                const id_letter_code = previous_ruling.id.charCodeAt( previous_ruling.id.length - 1 );
                if ( id_letter_code < 64 + this.state.teams.length ) append_final_query = true;
            }
        }

        // setup next query if there's more of the quiz remaining
        if ( distribution.length || append_final_query ) {
            const record = { current: true };
            this.#setup_query( record, distribution );
            this.state.board.push(record);
        }

        // append any remaining distribution
        while ( distribution.length ) {
            this.state.board.push( distribution.shift() );
        }

        return this.scoring.score(this);
    }

    #setup_query( record, distribution ) {
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

        if ( ! record.query ) {
            const found_index = this.state.query_cache.findIndex( query =>
                record.type.substr( 0, 1 ) == query.type.substr( 0, 1 ) &&
                record.bible == query.bible
            );

            if ( found_index > -1 ) {
                record.query = this.state.query_cache.splice( found_index, 1 ).shift();
            }
            else {
                record.query = this.queries.create( record.type.substr( 0, 1 ), record.bible );
                this.state.query_cache = [];
            }
        }
    }

    board_row( id = undefined ) {
        return this.state.board.find( row => (id) ? id == row.id : row.current );
    }

    static #actions = [
        'no_trigger', 'correct', 'incorrect',
        'foul', 'timeout', 'appeal_accepted', 'appeal_declined',
    ];

    action(
        action,
        team_id    = undefined,
        quizzer_id = undefined,
        qsstypes   = undefined,
        event_id   = undefined,
    ) {
        action = Quiz.#actions.find(
            canonical_action => canonical_action == action.toLowerCase()
        );
        if ( ! action ) throw '"' + action + '" is not a valid action';

        const event = (event_id)
            ? this.state.events[ this.state.board.findIndex( row => event_id == row.id ) ]
            : {};

        event.action = action;

        if ( event.action != 'no_trigger' && team_id ) {
            event.team_id = team_id;
        }
        else {
            delete event.team_id;
        }

        if ( event.action != 'no_trigger' && quizzer_id ) {
            event.quizzer_id = quizzer_id;
        }
        else {
            delete event.quizzer_id;
        }

        if ( event.action != 'no_trigger' && qsstypes ) {
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
        else {
            delete event.qsstypes;
        }

        if ( ! event_id ) this.state.events.push(event);
        const message = this.#build_board();
        if (message) notice(message);
    }

    replace_query() {
        const record = this.state.board.find( record => record.current );
        record.query = this.queries.create( record.query.type, record.query.bible );
    }

    delete_last_action() {
        this.state.events.pop();
        this.#build_board();
    }
}
