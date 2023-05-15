import Quiz from 'classes/quiz';

const url = new URL( window.location.href );
window.quiz = new Quiz({ quiz : url.searchParams.get('quiz') });

let timer_timeout_id;

window.quiz.ready.then( () => {
    while ( window.quiz.events.find( event => event.current ) )
        window.quiz.action( 'incorrect', '_0', '_1' );

    Vue
        .createApp({
            data() {
                return {
                    events: quiz.events,
                };
            },
        })
        .mount('#quizsage');
} );
