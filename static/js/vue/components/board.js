import store    from 'vue/store';
import template from 'modules/template';

export default {
    computed: {
        ...Pinia.mapState( store, [ 'board', 'current', 'selected', 'teams', 'hidden_solution' ] ),
    },

    methods: {
        ...Pinia.mapActions( store, [ 'is_quiz_done', 'view_query', 'toggle_hidden_solution' ] ),

        select_quizzer( quizzer_id, team_id ) {
            if ( this.hidden_solution ) this.toggle_hidden_solution();

            if ( this.is_quiz_done() ) return;

            this.selected.quizzer_id = quizzer_id;
            this.selected.team_id    = team_id;

            this.selected.bible = this.teams.find( team => team.id == team_id )
                .quizzers.find( quizzer => quizzer.id == quizzer_id ).bible;

            if (
                this.current.event.current &&
                this.$root.$refs.timer
            ) this.$root.$refs.timer.quizzer_selected();

            if ( this.$root.$refs.controls ) {
                if ( ! this.selected.type.synonymous_verbatim_open_book )
                    this.$root.$refs.controls.select_type('synonymous');

                if (
                    this.current.query.type == 'Q' &&
                    this.selected.type.with_reference != true
                ) this.$root.$refs.controls.select_type('with_reference');
            }
        },
    },

    watch: {
        board() {
            this.$nextTick( () => {
                window.dispatchEvent( new Event('resize') );
            } );
        },
    },

    template: await template( import.meta.url ),
};
