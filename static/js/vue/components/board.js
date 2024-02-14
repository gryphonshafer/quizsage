import store    from 'vue/store';
import template from 'modules/template';

export default {
    computed: {
        ...Pinia.mapState( store, [ 'board', 'current', 'selected', 'teams' ] ),
    },

    methods: {
        ...Pinia.mapActions( store, [ 'delete_last_action', 'exit_quiz', 'is_quiz_done', 'view_query' ] ),

        select_quizzer( quizzer_id, team_id ) {
            if ( this.is_quiz_done() ) return;

            this.selected.quizzer_id = quizzer_id;
            this.selected.team_id    = team_id;

            this.selected.bible = this.teams.find( team => team.id == team_id )
                .quizzers.find( quizzer => quizzer.id == quizzer_id ).bible;

            if (
                this.current.event.current &&
                this.$root.$refs.timer &&
                this.$root.$refs.timer.state == 'Start'
            ) this.$root.$refs.timer.toggle();

            if ( this.$root.$refs.controls && ! this.selected.type.synonymous_verbatim_open_book )
                this.$root.$refs.controls.select_type('synonymous');
        },

        delete_last_row() {
            if ( this.$root.$refs.controls ) this.$root.$refs.controls.trigger_event('reset');
            this.delete_last_action();
        },
    },

    template: await template( import.meta.url ),
};
