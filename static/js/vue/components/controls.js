import store    from 'vue/store';
import template from 'modules/template';

export default {
    computed: {
        ...Pinia.mapState( store, [ 'current', 'selected' ] ),
    },

    methods: {
        ...Pinia.mapActions( store, [
            'action', 'alter_query', 'last_event_if_not_viewed', 'is_quiz_done', 'view_query',
        ] ),

        select_type(type) {
            if ( this.is_quiz_done() ) return;

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
                ) && ! this.selected.quizzer_id ||
                event_type != 'reset' && this.is_quiz_done()
            ) return;

            if ( this.$root.$refs.timer ) {
                if ( event_type != 'timeout' ) {
                    this.$root.$refs.timer.reset();
                }
                else {
                    this.$root.$refs.timer.start('timeout');
                }
            }

            if ( event_type == 'reset' ) {
                const last_event = this.last_event_if_not_viewed();
                if (last_event) {
                    this.view_query(last_event);
                }
                else {
                    if ( this.selected.type.with_reference ) this.select_type('with_reference');
                    if ( this.selected.type.add_verse      ) this.select_type('add_verse');
                }
            }
            else {
                this.action(
                    event_type,
                    this.selected.team_id,
                    this.selected.quizzer_id,
                    this.current.event.type.substr(1),
                    ( this.current.event.current ) ? undefined : this.current.event.id,
                );

                if ( this.selected.type.with_reference ) this.selected.type.with_reference = false;
                if ( this.selected.type.add_verse      ) this.selected.type.add_verse      = false;
            }

            this.selected.type.synonymous_verbatim_open_book = '';

            this.selected.team_id    = undefined;
            this.selected.quizzer_id = undefined;
            this.selected.bible      = this.current.query.bible;
            this.current.event.type  = this.current.event.type.substr( 0, 1 ).toUpperCase();

            if ( this.$root.$refs.search ) this.$root.$refs.search.reset();
        },
    },

    template: await template( import.meta.url ),
};
