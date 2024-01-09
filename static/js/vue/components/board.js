import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'selected', 'teams', 'board' ] ),
    },

    methods: {
        ...Pinia.mapActions( quiz, [ 'view_query', 'delete_last_action', 'exit_quiz' ] ),

        select_quizzer( quizzer_id, team_id ) {
            this.selected.quizzer_id = quizzer_id;
            this.selected.team_id    = team_id;

            this.selected.bible = this.teams.find( team => team.id == team_id )
                .quizzers.find( quizzer => quizzer.id == quizzer_id ).bible;

            if ( this.$root.$refs.timer && this.$root.$refs.timer.state == 'Start' )
                this.$root.$refs.timer.toggle();

            if ( this.$root.$refs.controls && ! this.selected.type.synonymous_verbatim_open_book )
                this.$root.$refs.controls.select_type('synonymous');
        },
    },

    template: await template( import.meta.url ),
};
