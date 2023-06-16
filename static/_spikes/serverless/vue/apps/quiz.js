import Quiz from 'classes/quiz';
// import ButtonCounterComponent from 'components/button_counter';
// import Answer from 'classes/answer';

// const answer = new Answer;

const url = new URL( window.location.href );
window.quiz = new Quiz({ quiz : url.searchParams.get('quiz') });

let timer_timeout_id;

window.quiz.ready.then( () => {
    Vue
        .createApp({
            data() {
                return {
                    event : quiz.events.find( event => event.current ),
                    teams : quiz.teams,
                    events: quiz.events,
                    timer : {
                        value: quiz.quizzer_response_duration,
                        state : 'Start',
                    },
                    selected: {
                        material: {},
                        type    : {
                            synonymous_verbatim_open_book: '',
                            with_reference               : false,
                            add_verse                    : false,
                        },
                    },
                    eligible_teams: '',
                };
            },
            // components: {
            //     'button-counter' : ButtonCounterComponent
            // },
            methods: {
                set_eligible_teams() {
                    let trigger_eligible_teams = this.teams.filter( team => team.trigger_eligible );

                    if ( trigger_eligible_teams.length == this.teams.length ) {
                        this.eligible_teams = `all ${this.teams.length} teams`;
                    }
                    else if ( trigger_eligible_teams.length == 1 ) {
                        this.eligible_teams = trigger_eligible_teams[0].name;
                    }
                    else {
                        const last_trigger_eligible_team = trigger_eligible_teams.pop();
                        this.eligible_teams = trigger_eligible_teams.map( team => team.name ).join(', ')
                            + ' and ' + last_trigger_eligible_team.name;
                    }
                },

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

                replace_query(type) {
                    quiz.replace_query(type);
                    this.trigger_event('reset');
                    this.event.type = type;
                },

                delete_last_action() {
                    quiz.delete_last_action();
                    this.trigger_event('reset');
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

                        if ( this.selected.type.add_verse ) {
                            try {
                                quiz.queries.add_verse( quiz.events.find( event => event.current ).query );
                            }
                            catch (e) {
                                alert('Unable to "Add Verse"');
                            }
                        }
                        else {
                            try {
                                const current_query = quiz.queries.remove_verse(
                                    quiz.events.find( event => event.current ).query
                                );
                                this.selected.material = current_query.material.find(
                                    verse => verse.bible == this.selected.material.bible
                                );
                            }
                            catch (e) {
                                alert('Unable to revoke "Add Verse"');
                            }
                        }
                    }

                    this.event.type =
                        this.event.type.substr( 0, 1 ).toUpperCase() +
                        this.selected.type.synonymous_verbatim_open_book.substr( 0, 1 ).toUpperCase() +
                        ( ( this.selected.type.with_reference ) ? 'R' : '' ) +
                        ( ( this.selected.type.add_verse      ) ? 'A' : '' );
                },

                select_quizzer( quizzer_id, team_id ) {
                    this.selected.quizzer_id = quizzer_id;
                    this.selected.team_id    = team_id;

                    if ( this.timer.state == 'Start' ) this.timer_toggle();
                    if ( ! this.selected.type.synonymous_verbatim_open_book ) this.select_type('synonymous');
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
                        ) && ! this.selected.quizzer_id
                    ) return;

                    this.timer_reset();

                    if ( event_type != 'reset' ) {
                        quiz.action( event_type, this.selected.team_id, this.selected.quizzer_id );
                        this.event  = quiz.events.find( event => event.current ) || quiz.events.at(-1);
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

                    this.set_eligible_teams();
                },
            },

            mounted() {
                this.selected.material = this.event.query.material[0];
                this.set_eligible_teams();
            },
        })
        // .use( Pinia.createPinia() )
        .mount('#quizsage');
} );
