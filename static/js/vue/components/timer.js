import store    from 'vue/store';
import template from 'modules/template';

export default {
    data() {
        return {
            value     : undefined,
            state     : 'Start',
            timeout_id: undefined,
        };
    },

    computed: {
        ...Pinia.mapState( store, ['durations'] ),
    },

    created() {
        this.value = this.durations.quizzer_response;
    },

    methods: {
        toggle() {
            const callback = () => {
                this.value--;
                if ( this.value > 0 ) {
                    this.timeout_id = setTimeout( callback, 1000 );
                }
                else {
                    this.state = 'Reset';
                    flash_window();
                }
            };

            if ( this.state == 'Start' ) {
                this.state      = 'Stop';
                this.timeout_id = setTimeout( callback, 1000 );
            }
            else if ( this.state == 'Stop' ) {
                clearTimeout( this.timeout_id );
                this.timeout_id = undefined;
                this.state      = 'Start';
            }
            else if ( this.state == 'Reset' ) {
                this.reset();
            }
        },

        reset( time = this.durations.quizzer_response ) {
            if ( this.timeout_id ) clearTimeout( this.timeout_id );
            this.timeout_id = undefined;
            this.state      = 'Start';
            this.value      = this.durations[time] || time;
        },

        start( duration_name = undefined ) {
            this.reset();
            if (duration_name) this.value = this.durations[duration_name];
            this.toggle();
        },
    },

    template: await template( import.meta.url ),
};
