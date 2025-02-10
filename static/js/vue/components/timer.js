import store    from 'vue/store';
import template from 'modules/template';

export default {
    data() {
        return {
            value                : undefined,
            state                : 'Start',
            timeout_id           : undefined,
            current_duration_name: undefined,
        };
    },

    computed: {
        ...Pinia.mapState( store, ['durations'] ),
    },

    created() {
        this.value = this.durations.quizzer || this.durations.standard;
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

                    let top_left_corner = window.document.querySelector('table.board td.top_left_corner');
                    if (top_left_corner) top_left_corner.style.backgroundColor = 'transparent';

                    const main     = window.document.querySelector('main');
                    const original = window.getComputedStyle(main).backgroundColor;
                    const color    = original.slice( 4, -1 ).split(',').map( value => parseInt(value) );
                    const inverted = `rgb( ${ color.map( value => 255 - value ).join(', ') } )`;

                    main.style.backgroundColor = inverted;

                    setTimeout( () => {
                        main.style.backgroundColor = original;
                        main.style.transition      = 'background-color 1000ms ease';

                        setTimeout( () => {
                            main.style.backgroundColor = 'inherit';
                            main.style.transition      = 'inherit';
                        }, 1000 );
                    }, 0 );
                }
            };

            if ( this.state == 'Start' || this.state == 'Resume' ) {
                this.state      = 'Pause';
                this.timeout_id = setTimeout( callback, 1000 );
            }
            else if ( this.state == 'Pause' ) {
                clearTimeout( this.timeout_id );
                this.timeout_id = undefined;
                this.state      = 'Resume';
            }
            else if ( this.state == 'Reset' ) {
                this.reset();
            }
        },

        reset( time = this.durations.quizzer || this.durations.standard ) {
            if ( this.timeout_id ) clearTimeout( this.timeout_id );
            this.timeout_id            = undefined;
            this.current_duration_name = undefined;
            this.state                 = 'Start';
            this.value                 = this.durations[time] || time;
        },

        start( duration_name = undefined ) {
            this.reset();
            if (duration_name) {
                this.value                 = this.durations[duration_name];
                this.current_duration_name = duration_name;
            }
            this.toggle();
        },

        quizzer_selected() {
            if ( ! this.current_duration_name || this.current_duration_name != 'quizzer' )
                this.start('quizzer');
        },
    },

    template: await template( import.meta.url ),
};
