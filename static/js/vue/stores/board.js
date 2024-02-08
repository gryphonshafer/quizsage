export default Pinia.defineStore( 'store', {
    state() {
        return {
            teams   : undefined,
            board   : undefined,
            current : undefined,
            selected: {
                bible: 'NIV',
                type: {
                    synonymous_verbatim_open_book: '',
                },
            },
        };
    },

    actions: {
        delete_last_action() {},
        exit_quiz() {},
        is_quiz_done() {},
        view_query() {},
    },
} );
