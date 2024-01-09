import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    computed: {
        ...Pinia.mapState( quiz, [ 'current', 'selected' ] ),
    },

    methods: {
        ...Pinia.mapActions( quiz, [ 'alter_query', 'action' ] ),

        select_type(type) {
            if ( type == 'synonymous' || type == 'verbatim' || type == 'open_book' ) {
                this.selected.type.synonymous_verbatim_open_book = type;

                if ( type == 'open_book' ) {
                    if ( this.selected.type.with_reference ) this.select_type('with_reference');
                    if ( this.selected.type.add_verse      ) this.select_type('add_verse');
                }
            }
            else if ( type == 'with_reference' ) {
                this.selected.type.with_reference = ! this.selected.type.with_reference;

                if (
                    this.selected.type.with_reference &&
                    this.selected.type.synonymous_verbatim_open_book == 'open_book'
                ) this.select_type('synonymous');
            }
            else if ( type == 'add_verse' ) {
                this.selected.type.add_verse = ! this.selected.type.add_verse;

                if (
                    this.selected.type.add_verse &&
                    this.selected.type.synonymous_verbatim_open_book == 'open_book'
                ) this.select_type('synonymous');

                if ( this.selected.type.add_verse ) {
                    try {
                        this.alter_query('add_verse');
                    }
                    catch (e) {
                        console.log(e);
                        alert('Unable to "Add Verse"');
                        this.selected.type.add_verse = ! this.selected.type.add_verse;
                    }
                }
                else {
                    try {
                        this.alter_query('remove_verse');
                    }
                    catch (e) {
                        console.log(e);
                        alert('Unable to revoke "Add Verse"');
                        this.selected.type.add_verse = ! this.selected.type.add_verse;
                    }
                }
            }

            this.current.event.type =
                this.current.event.type.substr( 0, 1 ).toUpperCase() +
                this.selected.type.synonymous_verbatim_open_book.substr( 0, 1 ).toUpperCase() +
                ( ( this.selected.type.with_reference ) ? 'R' : '' ) +
                ( ( this.selected.type.add_verse      ) ? 'A' : '' );
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

            if ( this.$root.$refs.timer ) this.$root.$refs.timer.reset();

            if ( event_type != 'reset' ) {
                this.action(
                    event_type,
                    this.selected.team_id,
                    this.selected.quizzer_id,
                    this.current.event.type.substr(1),
                );

                if ( this.selected.type.with_reference ) this.selected.type.with_reference = false;
                if ( this.selected.type.add_verse      ) this.selected.type.add_verse      = false;
            }
            else {
                if ( this.selected.type.with_reference ) this.select_type('with_reference');
                if ( this.selected.type.add_verse      ) this.select_type('add_verse');
            }

            this.selected.type.synonymous_verbatim_open_book = '';

            this.selected.team_id    = undefined;
            this.selected.quizzer_id = undefined;
            this.selected.bible      = this.current.query.bible;
            this.current.event.type  = this.current.event.type.substr( 0, 1 ).toUpperCase();
        },
    },

    template: await template( import.meta.url ),
};
