import Quiz from 'classes/quiz';

const url = new URL( window.location.href );
fetch( new URL( '/quiz/data/' + url.searchParams.get('id') + '.json', url ) )
    .then( reply => reply.json() )
    .then( data => {
        data.settings.state = data.state;
        const quiz = new Quiz( data.settings );
        quiz.ready.then( () => {
            Vue
                .createApp({
                    data() {
                        return {
                            timer: {
                                value: quiz.quizzer_response_duration,
                                state: 'Start',
                            },
                            selected: {
                                material: undefined,
                                type    : {
                                    synonymous_verbatim_open_book : '',
                                    with_reference                : false,
                                    add_verse                     : false,
                                },
                            },
                            search_text   : '',
                            search_exact  : false,
                            matched_verses: [],
                        };
                    },

                    created() {
                        this.setup();
                    },

                    methods: {
                        setup() {
                            this.board = quiz.state.board;
                            this.teams = quiz.state.teams;

                            this.selected.quizzer_id = undefined;
                            this.selected.team_id    = undefined;

                            const current_event = quiz.state.board.find( event => event.current );
                            if (current_event) {
                                this.current_event     = current_event;
                                this.eligible_teams    = this.get_eligible_teams();
                                this.selected.material = this.current_event.query.material
                                    .find( verse => verse.bible == this.current_event.query.bible );

                                this.selected.type.synonymous_verbatim_open_book = '';
                                this.selected.type.with_reference                = false;
                                this.selected.type.add_verse                     = false;
                            }
                        },

                        get_eligible_teams() {
                            let trigger_eligible_teams = this.teams.filter( team => team.trigger_eligible );

                            if ( trigger_eligible_teams.length == this.teams.length )
                                return `all ${ this.teams.length } teams`;

                            if ( trigger_eligible_teams.length == 1 )
                                return trigger_eligible_teams[0].name;

                            const last_trigger_eligible_team = trigger_eligible_teams.pop();
                            return trigger_eligible_teams.map( team => team.name ).join(', ')
                                + ' and ' + last_trigger_eligible_team.name;
                        },

                        timer_toggle() {
                            const timer_run = () => {
                                this.timer.value--;
                                if ( this.timer.value > 0 ) {
                                    this.timer.id = setTimeout( timer_run, 1000 );
                                }
                                else {
                                    this.timer.state = 'Reset';
                                }
                            };

                            if ( this.timer.state == 'Start' ) {
                                this.timer.state = 'Stop';
                                this.timer.id    = setTimeout( timer_run, 1000 );
                            }
                            else if ( this.timer.state == 'Stop' ) {
                                clearTimeout( this.timer.id );
                                this.timer.id    = undefined;
                                this.timer.state = 'Start';
                            }
                            else if ( this.timer.state == 'Reset' ) {
                                this.timer_reset();
                            }
                        },

                        timer_reset( time = quiz.quizzer_response_duration ) {
                            if ( this.timer.id ) clearTimeout( this.timer.id );
                            this.timer.id    = undefined;
                            this.timer.state = 'Start';
                            this.timer.value = time;
                        },

                        select_type(type) {
                            if ( ! quiz.state.board.find( event => event.current ) ) return;

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
                                        quiz.queries.add_verse( this.current_event.query );
                                    }
                                    catch (e) {
                                        console.log(e);
                                        alert('Unable to "Add Verse"');
                                    }
                                }
                                else {
                                    try {
                                        const current_query = quiz.queries.remove_verse(
                                            this.current_event.query
                                        );
                                        this.selected.material = current_query.material.find(
                                            verse => verse.bible == this.selected.material.bible
                                        );
                                    }
                                    catch (e) {
                                        console.log(e);
                                        alert('Unable to revoke "Add Verse"');
                                    }
                                }
                            }

                            this.current_event.type =
                                this.current_event.type.substr( 0, 1 ).toUpperCase() +
                                this.selected.type.synonymous_verbatim_open_book.substr( 0, 1 ).toUpperCase() +
                                ( ( this.selected.type.with_reference ) ? 'R' : '' ) +
                                ( ( this.selected.type.add_verse      ) ? 'A' : '' );
                        },

                        select_quizzer( quizzer_id, team_id ) {
                            if ( ! quiz.state.board.find( event => event.current ) ) return;

                            this.selected.quizzer_id = quizzer_id;
                            this.selected.team_id    = team_id;

                            const bible = this.teams.find( team => team.id == team_id )
                                .quizzers.find( quizzer => quizzer.id == quizzer_id ).bible;
                            this.selected.material = this.current_event.query
                                .material.find( verse => verse.bible == bible );

                            if ( this.timer.state == 'Start' ) this.timer_toggle();
                            if ( ! this.selected.type.synonymous_verbatim_open_book )
                                this.select_type('synonymous');
                        },

                        trigger_event(event_type) {
                            if (
                                ! quiz.state.board.find( event => event.current ) &&
                                event_type != 'reset'
                            ) return;

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
                                quiz.action(
                                    event_type,
                                    this.selected.team_id,
                                    this.selected.quizzer_id,
                                    this.current_event.type.substr(1),
                                );

                                this.save_quiz_data();
                            }
                            else if ( quiz.state.board.find( event => event.current ) ) {
                                this.current_event.type = this.current_event.type.substr( 0, 1 );
                            }

                            this.setup();
                        },

                        replace_query() {
                            quiz.replace_query();
                            this.trigger_event('reset');
                        },

                        delete_last_action() {
                            quiz.delete_last_action();
                            this.trigger_event('reset');
                            this.save_quiz_data();
                        },

                        exit_quiz() {
                            document.location.href = new URL( '/', url );
                        },

                        search_material() {
                            this.matched_verses = quiz.queries.material.search(
                                this.search_text,
                                this.selected.material.bible,
                                ( this.search_exact ) ? 'exact' : 'inexact',
                            );
                        },

                        save_quiz_data() {
                            fetch(
                                new URL( '/quiz/save_data/' + url.searchParams.get('id'), url ),
                                {
                                    method: 'POST',
                                    body  : JSON.stringify( quiz.state ),
                                },
                            );
                        },
                    },

                    watch: {
                        search_text() {
                            this.matched_verses = [];
                            if ( this.search_text.length > 3 ) this.search_material();
                        },
                        search_exact() {
                            this.matched_verses = [];
                            if ( this.search_text.length > 3 ) this.search_material();
                        }
                    },
                })
                .mount('#quiz');
        } );
    } );
