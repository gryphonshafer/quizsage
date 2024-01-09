import Quiz from 'classes/quiz';

const json_material_path = '../../json/material';

const url = new URL( window.location.href );

const quiz_promise = fetch( new URL( url.pathname + '.json', url ) )
    .then( reply => reply.json() );

const material_promise = quiz_promise
    .then( data => fetch( new URL(
        json_material_path + '/' + data.settings.material.material_id + '.json',
        url,
    ) ) )
    .then( reply => reply.json() );

const [ quiz, miscellaneous ] = await Promise.all( [ quiz_promise, material_promise ] )
    .then( ( [ quiz_data, material_data ] ) => {
        const inputs = quiz_data.settings.inputs;

        inputs.material.data     = material_data;
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

function get_current_event(id) {
    return quiz.state.board.find( event => (id) ? id == event.id : event.current );
}

function get_current(id) {
    const event = get_current_event(id);
    return (event)
        ? {
            event    : event,
            query    : event.query,
            materials: quiz.queries.material.materials( event.query ),
        }
        : undefined;
}

export default Pinia.defineStore( 'quiz', {
    state() {
        const current = get_current();

        return {
            durations: {
                quizzer_response: quiz.quizzer_response_duration,
                timeout         : quiz.timeout_duration,
                appeal          : quiz.appeal_duration,
            },
            material: quiz.queries.material,
            teams   : quiz.state.teams,
            board   : quiz.state.board,
            current : current,
            selected: {
                bible: (current)
                    ? current.event.query.bible
                    : quiz.queries.material.bibles.find( (bible) => bible.type == 'primary' ).name,
                type: {},
            },
        };
    },

    actions: {
        _update_current(id) {
            this.current = get_current(id) || this.current;
        },

        _update_data(id) {
            this._update_current(id);
            this.teams = quiz.state.teams;
            this.board = quiz.state.board;
        },

        replace_query() {
            quiz.replace_query();
            this._update_data();
        },

        action( action, team_id = undefined, quizzer_id = undefined, qsstypes = undefined ) {
            quiz.action( action, team_id, quizzer_id, qsstypes );
            this._update_data();
            this.save_quiz_data();
        },

        alter_query(action) {
            quiz.queries[action]( get_current_event().query );
            this._update_current();
        },

        view_query(record) {
            this.selected.bible = record.bible;
            this._update_current( record.id );
        },

        delete_last_action() {
            quiz.delete_last_action();
            this._update_data();
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

        exit_quiz() {
            document.location.href = new URL(
                ( miscellaneous.meet_id ) ? '/meet/' + miscellaneous.meet_id : '/',
                url,
            );
        },
    },
} );
