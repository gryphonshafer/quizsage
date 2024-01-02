import template from 'modules/template';
import quiz     from 'vue/stores/quiz';

export default {
    data() {
        const store = quiz();

        return {
            value     : store.quiz.quizzer_response_duration,
            state     : 'Start',
            timeout_id: undefined,
            durations : {
                quizzer_response: store.quiz.quizzer_response_duration,
                timeout         : store.quiz.timeout_duration,
                appeal          : store.quiz.appeal_duration,
            },
        };
    },
    template: await template( import.meta.url ),
    methods: {
        toggle() {
            const callback = () => {
                this.value--;
                if ( this.value > 0 ) {
                    this.timeout_id = setTimeout( callback, 1000 );
                }
                else {
                    this.state = 'Reset';
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
    },
};
