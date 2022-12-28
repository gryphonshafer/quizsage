import Quiz from 'classes/quiz';
// import ButtonCounterComponent from 'components/button_counter';
// import Answer from 'classes/answer';

// const answer = new Answer;

const quiz = new Quiz({ quiz : 'playtest' });

let timer_timeout_id;

quiz.ready.then( () => {
    Vue
        .createApp({
            data() {
                return {
                    event  : quiz.current_query_event(),
                    teams  : quiz.teams,
                    events : quiz.events,
                    timer  : {
                        value : quiz.quizzer_response_duration,
                        state : 'Start',
                    },
                    selected : {
                        material : {},
                        type     : {
                            synonymous_verbatim_open_book : '',
                            with_reference                : false,
                            add_verse                     : false,
                        },
                    },
                };
            },
            // components: {
            //     'button-counter' : ButtonCounterComponent
            // },
            methods: {
                timer_toggle() {
                    const timer_run = () => {
                        this.timer.value--;
                        if ( this.timer.value > 0 ) {
                            timer_timeout_id = setTimeout( timer_run, 1000 );
                        }
                        else {
                            this.timer.state = 'Reset';
                        }
                    };

                    if ( this.timer.state == 'Start' ) {
                        this.timer.state = 'Stop';
                        timer_timeout_id = setTimeout( timer_run, 1000 );
                    }
                    else if ( this.timer.state == 'Stop' ) {
                        clearTimeout(timer_timeout_id);
                        timer_timeout_id = undefined;
                        this.timer.state = 'Start';
                    }
                    else if ( this.timer.state == 'Reset' ) {
                        this.timer_reset();
                    }
                },

                timer_reset( time = quiz.quizzer_response_duration ) {
                    if (timer_timeout_id) clearTimeout(timer_timeout_id);
                    timer_timeout_id = undefined;
                    this.timer.state = 'Start';
                    this.timer.value = time;
                },

                select_type(type) {
                    if ( type == 'synonymous' || type == 'verbatim' || type == 'open_book' ) {
                        this.selected.type.synonymous_verbatim_open_book = type;
                    }
                    else if ( type == 'with_reference' ) {
                        this.selected.type.with_reference = ! this.selected.type.with_reference;
                    }
                    else if ( type == 'add_verse' ) {
                        this.selected.type.add_verse = ! this.selected.type.add_verse;
                    }

                    this.event.type =
                        this.event.type.substr( 0, 1 ).toUpperCase() +
                        this.selected.type.synonymous_verbatim_open_book.substr( 0, 1 ).toUpperCase() +
                        ( ( this.selected.type.with_reference ) ? 'W' : '' ) +
                        ( ( this.selected.type.add_verse      ) ? 'A' : '' );
                },

                select_quizzer( quizzer_id, team_id ) {
                    this.selected.quizzer = quizzer_id;
                    this.selected.team    = team_id;

                    if ( this.timer.state == 'Start' ) this.timer_toggle();
                },

                trigger_event(event_type) {
                    if (
                        (
                            event_type == 'correct'         ||
                            event_type == 'incorrect'       ||
                            event_type == 'foul'            ||
                            event_type == 'timeout'         ||
                            event_type == 'appeal_accepted' ||
                            event_type == 'appeal_declined'
                        ) && ! this.selected.quizzer
                    ) return;

                    this.timer_reset();

                    if ( event_type != 'reset' ) {
                        quiz.action( event_type, this.selected.team, this.selected.quizzer );
                        this.event  = quiz.current_query_event();
                        this.teams  = quiz.teams;
                        this.events = quiz.events;
                    }

                    this.selected = {
                        material : this.event.query.material[0],
                        type     : {
                            synonymous_verbatim_open_book : '',
                            with_reference                : false,
                            add_verse                     : false,
                        },
                    };
                },

                replace_query(type) {
                    this.trigger_event('reset');

                    this.event.type = type;
                    quiz.replace_query();

                    this.event             = quiz.current_query_event();
                    this.events            = quiz.events;
                    this.selected.material = this.event.query.material[0];
                },
            },

            mounted() {
                this.selected.material = this.event.query.material[0];
            },
        })
        // .use( Pinia.createPinia() )
        .mount('#playtest');
} );
