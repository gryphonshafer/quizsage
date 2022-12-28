'use strict';
const QuizSageQuiz = ( () => {
    return function ( input = {} ) {
        this.initial_team_timeouts = input.initial_team_timeouts || 1;
        this.active_event_index    = input.active_event_index    || 0;

        let next_unique_id = 1;
        this.teams = input.teams;
        this.teams.forEach( (team) => {
            if ( team.id && team.id > next_unique_id ) next_unique_id = team.id + 1;
            team.quizzers.forEach( (quizzer) => {
                if ( quizzer.id && quizzer.id > next_unique_id ) next_unique_id = quizzer.id + 1;
            } );
        } );
        this.teams.forEach( (team) => {
            if ( ! team.id               ) team.id               = next_unique_id++;
            if ( ! team.timeouts         ) team.timeouts         = 1;
            if ( ! team.appeals_declined ) team.appeals_declined = 0;
            if ( ! team.score            ) team.score            = 0;

            team.quizzers.forEach( (quizzer) => {
                if ( ! quizzer.id        ) quizzer.id        = next_unique_id++;
                if ( ! quizzer.correct   ) quizzer.correct   = 0;
                if ( ! quizzer.incorrect ) quizzer.incorrect = 0;
                if ( ! quizzer.score     ) quizzer.score     = 0;
            } );
        } );

        this.queries = input.queries;
        this.ready   = this.queries.ready.then( () => {
            const bibles = this.queries.material.bibles
                .map( value => ( { value, sort: Math.random() } ) )
                .sort( ( a, b ) => a.sort - b.sort )
                .map( ( {value} ) => value );

            const types       = Array( bibles.length ).fill('X');
            const non_x_types = [ 'P', 'C', 'Q', 'F' ];

            while ( types.length < this.teams.length * 4 ) {
                types.push( non_x_types[0] );
                non_x_types.push( non_x_types.shift() );
            }

            this.events = types
                .map( value => ( { value, sort: Math.random() } ) )
                .sort( ( a, b ) => a.sort - b.sort )
                .map( ({value}) => value )
                .map(
                    ( value, index ) => {
                        bibles.push( bibles.shift() );
                        return {
                            id    : index + 1,
                            type  : value,
                            bible : bibles[0],
                        };
                    }
                );

            this.event = this.events[ this.active_event_index ];
            this.event.query = this.create_query();
            this.event.id += 'A';

            return this;
        } );

        this.data = () => {
            return {
                queries               : this.queries.data(),
                teams                 : this.teams,
                events                : this.events,
                initial_team_timeouts : this.initial_team_timeouts,
                active_event_index    : this.active_event_index,
            };
        }

        this.create_query = ( requery = false ) => {
            this.event = this.events[ this.active_event_index ];

            if ( ! this.event ) throw 'Ran out of queries...';

            if ( ! this.event.query || requery )
                this.event.query = this.queries.create( this.event.type, this.event.bible );
            return this.event.query;
        }

        this.recreate_query = () => {
            return this.create_query(true);
        }

        this.handle_event = ( type, quizzer_id, team_id ) => {
            if ( type == 'no_jump' ) {
                this.active_event_index++;
                this.create_query();

                this.event.id += 'A';
            }
            else if ( type == 'correct' ) {
                const team    = this.teams.find( (team) => team.id == team_id );
                const quizzer = team.quizzers.find( (quizzer) => quizzer.id == quizzer_id );

                quizzer.correct++;

                if ( this.event.type.indexOf('O') != -1 ) quizzer.open_book = true;
                if (
                    this.event.type.indexOf('X') == -1 &&
                    this.event.type.indexOf('S') == -1 &&
                    this.event.type.indexOf('V') == -1 &&
                    this.event.type.indexOf('O') == -1
                ) this.event.type += 'S';

                const points =
                    (
                        ( this.event.type.indexOf('V') != -1 ) ? 4 :
                        ( this.event.type.indexOf('O') != -1 ) ? 1 : 2
                    ) +
                    (
                        (
                            this.event.type.indexOf('W') != -1 &&
                            this.event.type.indexOf('O') == -1
                        ) ? 1 : 0
                    );

                const ceiling = (
                    quizzer.correct == 4 &&
                    quizzer.incorrect == 0 &&
                    ! quizzer.open_book
                ) ? 1 : 0;

                let event_index = this.active_event_index - 1;
                let last_ruled_event;
                while ( event_index >= 0 && ! last_ruled_event ) {
                    if (
                        this.events[event_index].event == 'correct' ||
                        this.events[event_index].event == 'incorrect'
                    ) last_ruled_event = this.events[event_index];
                    event_index--;
                }
                const follow = (
                    last_ruled_event &&
                    last_ruled_event.event == 'correct' &&
                    last_ruled_event.team == team_id &&
                    last_ruled_event.quizzer != quizzer_id
                ) ? 1 : 0;

                const nth_quizzer_bonus = ( quizzer.correct != 1 ) ? 0 : team.quizzers
                    .filter( (this_quizzer) => this_quizzer.correct && this_quizzer.id != quizzer_id )
                    .length;

                quizzer.score += points + ceiling;
                team.score    += points + ceiling + follow + nth_quizzer_bonus;

                this.event.quizzer       = quizzer_id;
                this.event.team          = team_id;
                this.event.event         = type;
                this.event.quizzer_label =
                    points +
                    ( (ceiling) ? '+' + ceiling : '' );
                this.event.team_label    =
                    ( points + ceiling ) +
                    ( (follow) ? '.' + follow : '' ) +
                    ( (nth_quizzer_bonus) ? ':' + nth_quizzer_bonus : '' );

                this.active_event_index++;
                this.create_query();

                this.event.id += 'A';
            }
            else if ( type == 'incorrect' ) {
                const team    = this.teams.find( (team) => team.id == team_id );
                const quizzer = team.quizzers.find( (quizzer) => quizzer.id == quizzer_id );

                quizzer.incorrect++;

                this.event.quizzer       = quizzer_id;
                this.event.team          = team_id;
                this.event.event         = type;
                this.event.quizzer_label = 0;
                this.event.team_label    = team.score;

                this.events.splice( this.active_event_index + 1, 0, {
                    bible : this.event.bible,
                    type  : this.event.type.substr( 0, 1 ),
                    id    :
                        this.event.id.substr( 0, 1 ) +
                        String.fromCharCode( this.event.id.charCodeAt(1) + 1 ),
                } );
                this.active_event_index++;
                this.create_query();
            }
            else if ( type == 'foul' ) {
                this.events.splice( this.active_event_index, 0, {
                    team          : team_id,
                    quizzer       : quizzer_id,
                    event         : type,
                    quizzer_label : 'F',
                } );
                this.active_event_index++;
            }
            else if ( type == 'timeout' ) {
                const team = this.teams.find( (team) => team.id == team_id );
                team.timeouts--;

                this.events.splice( this.active_event_index, 0, {
                    team       : team_id,
                    event      : type,
                    team_label : 'TO',
                } );
                this.active_event_index++;
            }
            else if ( type == 'appeal_accepted' ) {
                this.events.splice( this.active_event_index, 0, {
                    team       : team_id,
                    event      : type,
                    team_label : 'AA',
                } );
                this.active_event_index++;
            }
            else if ( type == 'appeal_declined' ) {
                const team = this.teams.find( (team) => team.id == team_id );
                team.appeals_declined++;

                this.events.splice( this.active_event_index, 0, {
                    team       : team_id,
                    event      : type,
                    team_label : 'AD',
                } );
                this.active_event_index++;
            }
            else {
                throw '"' + type + '" is not a valid event type';
            }
        }
    }
} )();
