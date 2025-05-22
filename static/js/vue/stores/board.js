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
            return true;
        },
        view_query() {},
    },
} );

let received_an_on_close = false;
omniframe.websocket.start({
    path: url.pathname + url.search,

    onclose: () => {
        received_an_on_close = true;
    },

    onopen: () => {
        if (received_an_on_close) {
            fetch( url.pathname + url.search + '/poke' );
            received_an_on_close = false;
        }
    },

    onmessage: (fresh_quiz_data) => {
        if (fresh_quiz_data) {
            store().$patch({
                teams: fresh_quiz_data.teams,
                board: fresh_quiz_data.board,
            });

            set_board_scale( fresh_quiz_data.teams );
        }
        else {
            window.location.reload();
        }
    },
});

export default store;
