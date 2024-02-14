const url = new URL( window.location.href );

const quiz_data = await fetch( url.pathname + '.json' + url.search )
    .then( response => response.json() )
    .then( data => {
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
    current : {
        event: {},
    },
};

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

omniframe.websocket.start({
    path      : url.pathname + url.search,
    onmessage : (fresh_quiz_data) => {
        if (fresh_quiz_data) {
            store().$patch({
                teams: fresh_quiz_data.teams,
                board: fresh_quiz_data.board,
            });
        }
        else {
            window.location.reload();
        }
    },
});

export default store;
