import Quiz from 'classes/quiz';

const json_material_path = '../../json/material';

const url = new URL( window.location.href );

const quiz_promise = fetch( new URL( url.pathname + '.json', url ) )
    .then( reply => reply.json() );

const material_promise = quiz_promise
    .then( data => fetch( new URL(
        json_material_path + '/' + data.settings.material.material_id + '.json',
        url,
    ) ) )
    .then( reply => reply.json() );

const quiz = await Promise.all( [ quiz_promise, material_promise ] )
    .then( ( [ quiz_data, material_data ] ) => {
        const inputs = quiz_data.settings.inputs;

        inputs.material.data     = material_data;
        inputs.quiz.state        = quiz_data.state;
        inputs.quiz.teams        = quiz_data.settings.teams;
        inputs.quiz.distribution = quiz_data.settings.distribution;
        inputs.miscellaneous     = {
            bracket : quiz_data.bracket,
            name    : quiz_data.name,
            room    : quiz_data.settings.room,
            schedule: quiz_data.settings.schedule,
            material: quiz_data.settings.material,
        };

        const quiz = new Quiz(inputs);
        return quiz;
    } );

export default Pinia.defineStore( 'quiz', {
    state() {
        return {
            quiz: quiz,
        };
    },
} );
