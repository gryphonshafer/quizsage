'use strict';
const QuizSageVueQuiz = ( () => {
    let timer_timeout_id;

    return function ( input = {} ) {
        const app = Vue.createApp({
            data() {
                return {
                    event            : input.quiz.event,
                    bibles           : input.quiz.queries.material.bibles,
                    teams            : input.quiz.teams,
                    events           : input.quiz.events,
                    timer_value      : 40,
                    timer_state      : 'Start',
                    svo_type         : undefined,
                    wr_type          : false,
                    selected_bible   : undefined,
                    selected_quizzer : undefined,
                    selected_team    : undefined,
                };
            },

            computed: {
                selected_material() {
                    return ( ! this.selected_bible || this.event.query.type == 'X' ) ? '' : this.event.query
                        .material
                        .find( (verse) => verse.bible == this.selected_bible )
                        .text;
                },

                selected_thesaurus() {
                    return ( ! this.selected_bible || this.event.query.type == 'X' ) ? '' : this.event.query
                        .material
                        .find( (verse) => verse.bible == this.selected_bible )
                        .thesaurus;
                },
            },

            methods: {
                select_bible(bible) {
                    this.selected_bible = bible;
                },

                timer_toggle() {
                    const timer_run = () => {
                        this.timer_value--;
                        if ( this.timer_value > 0 ) {
                            timer_timeout_id = setTimeout( timer_run, 1000 );
                        }
                        else {
                            this.timer_state = 'Reset';
                        }
                    };

                    if ( this.timer_state == 'Start' ) {
                        this.timer_state = 'Stop';
                        timer_timeout_id = setTimeout( timer_run, 1000 );
                    }
                    else if ( this.timer_state == 'Stop' ) {
                        clearTimeout(timer_timeout_id);
                        timer_timeout_id = undefined;
                        this.timer_state = 'Start';
                    }
                    else if ( this.timer_state == 'Reset' ) {
                        this.timer_reset();
                    }
                },

                timer_reset( time = 40 ) {
                    if (timer_timeout_id) clearTimeout(timer_timeout_id);
                    timer_timeout_id = undefined;
                    this.timer_state = 'Start';
                    this.timer_value = time;
                },

                select_type(type) {
                    if ( type == 'synonymous' || type == 'verbatim' || type == 'open_book' ) {
                        this.svo_type = type;
                    }
                    else if ( type == 'with_reference' ) {
                        this.wr_type = ! this.wr_type;
                    }

                    this.event.type =
                        this.event.type.substr( 0, 1 ).toUpperCase() +
                        this.svo_type.substr( 0, 1 ).toUpperCase() +
                        ( ( this.wr_type ) ? 'W' : '' );
                },

                select_quizzer( quizzer_id, team_id ) {
                    this.selected_quizzer = quizzer_id;
                    this.selected_team    = team_id;

                    if ( this.timer_state == 'Start' ) this.timer_toggle();
                },

                trigger_event(event_type) {
                    this.timer_reset();

                    if ( event_type != 'reset' ) {
                        input.quiz.handle_event( event_type, this.selected_quizzer, this.selected_team );
                        this.event = input.quiz.event;
                    }

                    this.svo_type         = undefined;
                    this.wr_type          = false;
                    this.selected_quizzer = undefined;
                    this.selected_team    = undefined;
                    this.selected_bible   = this.event.bible;
                },

                replace_query(type) {
                    this.trigger_event('reset');

                    input.quiz.event.query = undefined;
                    input.quiz.event.type  = type;

                    input.quiz.create_query();

                    this.event          = input.quiz.event;
                    this.selected_bible = undefined;
                    this.selected_bible = this.event.bible;
                },
            },

            mounted() {
                this.selected_bible = this.event.bible;
            },
        });

        app.mount( input.id );
        return app;
    }
} )();
