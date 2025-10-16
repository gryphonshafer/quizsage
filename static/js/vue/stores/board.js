const url = new URL( window.location.href );

const quiz_data = await fetch( url.pathname + '.json' + url.search )
    .then( response => response.json() )
    .then( data     => {
        if ( data.state && data.state.teams ) return data.state;

        data.settings.teams.forEach( team => {
            team.appeals_declined   = 0;
            team.timeouts_remaining = 1;
            team.score              = { position: 0 };

            team.quizzers.forEach( quizzer => quizzer.score = {
                points     : 0,
                team_points: 0,
                correct    : 0,
                open_book  : 0,
            } );
        } );

        const first_row = data.settings.distribution[0];
        first_row.current = true;
        first_row.id += 'A';

        return {
            teams: data.settings.teams,
            board: data.settings.distribution,
        };
    } );

const state = {
    teams   : quiz_data.teams,
    board   : quiz_data.board,
    selected: {},
    current : { event: {} },
};

function set_board_scale(teams) {
    const board = window.document.querySelector('div#board');

    if (board) {
        const columns_count = 3 + teams.length + teams.flatMap( team => team.quizzers ).length;
        const count_adjust  = ( window.chrome ) ? 3.125 : 3.5;

        board.style.fontSize   = 'calc( ( 100vw - 1em ) / ' + ( columns_count * count_adjust ) + ' )';
        board.style.lineHeight = '1.5em';

        if ( window.chrome ) board.classList.add('chrome');
    }
}

set_board_scale( quiz_data.teams );

const store = Pinia.defineStore( 'store', {
    state() {
        return state;
    },
    actions: {
        is_quiz_done() {
            return ! state.board.find( row => row.current );
        },
        view_query() {},
    },
} );

function handle_fresh_quiz_data (quiz_data) {
    if ( quiz_data && quiz_data.teams && quiz_data.board ) {
        store().$patch({
            teams   : quiz_data.teams,
            board   : quiz_data.board,
            selected : {
                quizzer_id: quiz_data.selected.quizzer_id,
                team_id   : quiz_data.selected.team_id,
            },
        });
        set_board_scale( quiz_data.teams );
    }
    else {
        window.location.reload();
    }
}

let received_an_on_close = false;
omniframe.websocket.start({
    path     : url.pathname + url.search,
    onmessage: quiz_data => handle_fresh_quiz_data(quiz_data),
    onclose  : () => received_an_on_close = true,
    onopen   : () => {
        if (received_an_on_close) {
            fetch( url.pathname + url.search + '.json' )
                .then( reply => reply.json() )
                .then( quiz_data => handle_fresh_quiz_data(
                    ( quiz_data.state ) ? quiz_data.state : quiz_data.settings
                ) );
            received_an_on_close = false;
        }
    },
});

export default store;
