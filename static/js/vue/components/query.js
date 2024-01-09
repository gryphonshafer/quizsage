import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'teams' ] ),

        eligible_teams() {
            let trigger_eligible_teams = this.teams.filter( team => team.trigger_eligible );

            if ( trigger_eligible_teams.length == this.teams.length )
                return `all ${ this.teams.length } teams`;

            if ( trigger_eligible_teams.length == 1 )
                return trigger_eligible_teams[0].name;

            const last_trigger_eligible_team = trigger_eligible_teams.pop();
            return trigger_eligible_teams.map( team => team.name ).join(', ')
                + ' and ' + last_trigger_eligible_team.name;
        },
    },

    template: await template( import.meta.url ),
};
