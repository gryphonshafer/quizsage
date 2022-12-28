import ButtonCounterComponent from 'components/button_counter';
import Answer from 'classes/answer';

const answer = new Answer;

Vue
    .createApp({
        data() {
            return {
                message: answer.speak(),
            };
        },
        components: {
            'button-counter' : ButtonCounterComponent
        },
    })
    .use( Pinia.createPinia() )
    .mount('#spike');
