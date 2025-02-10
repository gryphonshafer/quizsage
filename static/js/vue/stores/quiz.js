import Quiz from 'classes/quiz';

const url              = new URL( window.location.href );
const quiz_promise     = fetch( new URL( url.pathname + '.json', url ) ).then( reply => reply.json() );
const material_promise = quiz_promise
    .then( data => fetch( new URL(
        data.json_material_path + '/' + data.settings.material.id + '.json',
        url,
    ) ) )
    .then( reply => reply.json() );

const [ quiz, miscellaneous ] = await Promise.all( [ quiz_promise, material_promise ] )
    .then( ( [ quiz_data, material_data ] ) => {
        const inputs = quiz_data.settings.inputs || {};

        inputs.material    ||= {};
        inputs.material.data = material_data;

        inputs.quiz            ||= {};
        inputs.quiz.state        = quiz_data.state;
        inputs.quiz.teams        = quiz_data.settings.teams;
        inputs.quiz.distribution = quiz_data.settings.distribution;

        return [
            new Quiz(inputs),
            {
                meet_id: quiz_data.meet_id,
                quiz_id: quiz_data.quiz_id,
            },
        ];
    } );

function get_current( id = undefined ) {
    const row = quiz.board_row(id);
    return (row)
        ? {
            event: row,
            query: row.query,
            ...quiz.queries.material.materials( row.query ),
        }
        : undefined;
}

function get_eligible_teams(teams) {
    let trigger_eligible_teams = teams.filter( team => team.trigger_eligible );

    if ( trigger_eligible_teams.length == teams.length ) {
        if ( teams.length > 2 ) {
            return `all ${ teams.length } teams`;
        }
        else {
            return 'both teams';
        }
    }

    if ( trigger_eligible_teams.length == 1 )
        return trigger_eligible_teams[0].name;

    const last_trigger_eligible_team = trigger_eligible_teams.pop();
    return trigger_eligible_teams.map( team => team.name ).join(', ')
        + ' and ' + last_trigger_eligible_team.name;
}

function update_current( store, id = undefined ) {
    store.current = get_current(id) || store.current;
}

function update_data(store) {
    update_current(store);

    store.teams          = quiz.state.teams;
    store.board          = quiz.state.board;
    store.eligible_teams = get_eligible_teams( quiz.state.teams );
}

export default Pinia.defineStore( 'store', {
    state() {
        const exit_quiz_url = new URL(
            ( miscellaneous.meet_id ) ? '/meet/' + miscellaneous.meet_id + '/state' : '/quiz/pickup/setup',
            url,
        );

        let current;
        let eligible_teams;

        try {
            if ( quiz.error ) throw quiz.error;
            current        = get_current() || get_current( quiz.state.board.at(-1).id );
            eligible_teams = get_eligible_teams( quiz.state.teams );
        }
        catch (e) {
            console.log(e);
            if ( window.omniframe && omniframe.memo ) omniframe.memo({
                class  : 'error',
                message:
                    'Unable to construct a complete quiz, likely due to insufficient material.<br>' +
                    'Try expanding the material and retrying.',
                callback: () => {
                    window.location.href = exit_quiz_url;
                },
            });
        }

        return {
            durations: {
                trigger: quiz.trigger_wait_duration,
                quizzer: quiz.quizzer_response_duration,
                timeout: quiz.timeout_duration,
                appeal : quiz.appeal_duration,
            },
            material: quiz.queries.material,
            teams   : quiz.state.teams,
            board   : quiz.state.board,
            current : current,
            selected: {
                bible: (current)
                    ? current.event.query.bible
                    : quiz.queries.material.bibles.find( (bible) => bible.type == 'primary' ).name,
                type: {
                    synonymous_verbatim_open_book: '',
                },
            },
            eligible_teams : eligible_teams,
            hidden_solution: ( ( miscellaneous.meet_id && quiz.board_row() ) ? true : false ),
            is_drill       : false,
            exit_quiz_url  : exit_quiz_url,
        };
    },

    actions: {
        replace_query() {
            try {
                quiz.replace_query();
                update_data(this);
            }
            catch (e) {
                console.log(e);
                if ( window.omniframe && omniframe.memo ) omniframe.memo({
                    class  : 'error',
                    message:
                        (
                            e == 'Unable to select a verse from which to construct query' ||
                            e == 'Unable to find phrase block from which to construct query'
                        )
                        ? 'Unable to replace query, likely due to insufficient size of material.<br>' +
                            'Try exiting the quiz and expanding the material.'
                        : 'Unexpected error occurred: ' + e,
                });
            }
        },

        action(
            action,
            team_id    = undefined,
            quizzer_id = undefined,
            qsstypes   = undefined,
            event_id   = undefined,
        ) {
            try {
                this.hidden_solution = ( action != 'timeout' ) ? false : true;
                quiz.action( action, team_id, quizzer_id, qsstypes, event_id );
                update_data(this);
                this.save_quiz_data();
            }
            catch (e) {
                console.log(e);
                if (
                    e == 'Unable to select a verse from which to construct query' ||
                    e == 'Unable to find phrase block from which to construct query'
                ) {
                    if ( window.omniframe && omniframe.memo ) omniframe.memo({
                        class  : 'error',
                        message:
                            'Unable to create a query, likely due to insufficient size of material.<br>' +
                            'Try exiting the quiz and expanding the material.',
                    });
                    this.delete_last_action();
                }
                else {
                    if ( window.omniframe && omniframe.memo ) omniframe.memo({
                        class  : 'error',
                        message: 'Unexpected error occurred: ' + e,
                    });
                }
            }
        },

        alter_query(action) {
            quiz.queries[action]( quiz.board_row( this.current.event.id ).query );
            update_current( this, this.current.event.id );
        },

        view_query(record) {
            this.selected.bible = record.bible;
            update_current( this, record.id );

            this.selected.type.with_reference                = false;
            this.selected.type.add_verse                     = false;
            this.selected.type.synonymous_verbatim_open_book = '';

            if ( this.current.event.qsstypes ) {
                const qsstypes = this.current.event.qsstypes;
                this.selected.type.synonymous_verbatim_open_book =
                    ( qsstypes.indexOf('O') != -1 ) ? 'open_book'  :
                    ( qsstypes.indexOf('S') != -1 ) ? 'synonymous' :
                    ( qsstypes.indexOf('V') != -1 ) ? 'verbatim'   : '';
                if ( qsstypes.indexOf('R') != -1 ) this.selected.type.with_reference = true;
                if ( qsstypes.indexOf('A') != -1 ) this.selected.type.add_verse      = true;
            }

            this.selected.team_id    = this.current.event.team_id;
            this.selected.quizzer_id = this.current.event.quizzer_id;
        },

        delete_last_action() {
            quiz.delete_last_action();
            update_data(this);
            this.save_quiz_data();
        },

        save_quiz_data() {
            fetch(
                new URL( '/quiz/save/' + miscellaneous.quiz_id, url ),
                {
                    method: 'POST',
                    body  : JSON.stringify( quiz.state ),
                },
            );
        },

        last_event_if_not_viewed() {
            const last_event = this.board.findLast( event => event.query );
            return ( this.current.event.id != last_event.id ) ? last_event : undefined;
        },

        toggle_hidden_solution() {
            this.hidden_solution = ! this.hidden_solution;
        },

        is_quiz_done() {
            return ( quiz.board_row() ) ? false : true;
        },

        exit_quiz() {
            if ( ! this.is_quiz_done() && window.omniframe && omniframe.memo ) {
                omniframe.memo({
                    class   : 'notice',
                    message : 'Are you sure you want to exit the quiz? The quiz is not finished.',
                    options : [ 'Yes, exit the quiz', 'No, stay here' ],
                    callback: event => {
                        if ( event.target.textContent == 'Yes, exit the quiz' )
                            window.location.href = this.exit_quiz_url;
                    },
                });
            }
            else {
                window.location.href = this.exit_quiz_url;
            }
        },
    },
} );
