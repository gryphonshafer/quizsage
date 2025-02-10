import Quiz     from 'classes/quiz';
import template from 'modules/template';

const url              = new URL( window.location.href );
const quiz_promise     = fetch( new URL( url.pathname + '.json', url ) ).then( reply => reply.json() );
const material_promise = quiz_promise
    .then( data => fetch( new URL(
        data.json_material_path + '/' + data.settings.material.id + '.json',
        url,
    ) ) )
    .then( reply => reply.json() );

const queries = await Promise.all( [ quiz_promise, material_promise ] )
    .then( ( [ quiz_data, material_data ] ) => {
        const inputs = quiz_data.settings.inputs || {};

        inputs.material    ||= {};
        inputs.material.data = material_data;

        inputs.quiz       ||= {};
        inputs.quiz.teams   = quiz_data.settings.teams;

        return new Quiz(inputs);
    } )
    .then( quiz => {
        try {
            if ( quiz.error ) throw quiz.error;
            while ( quiz.board_row() ) {
                quiz.action( 'incorrect', quiz.teams[0].id, quiz.teams[0].quizzers[0].id );
            }
        }
        catch (e) {
            console.log(e);
            if ( window.omniframe && omniframe.memo ) omniframe.memo({
                class  : 'error',
                message:
                    "Unable to construct a complete quiz's worth of queries, " +
                    "likely due to insufficient material.<br>" +
                    "Try expanding the material and re-generating the queries.",
                callback: () => {
                    window.location.href = new URL( '/quiz/pickup/setup', url );
                },
            });
        }

        const queries = quiz.state.board.map( row => {
            const query = {
                id    : row.id,
                single: row.query,
            };

            try {
                query.double = quiz.queries.add_verse( query.single );
                query.single = query.double.original;
                delete query.double.original;
            }
            catch (e) {
                if ( e != 'Unable to find next verse' ) throw e;
            }

            return query;
        } );

        return queries;
    } );

Vue
    .createApp({
        data() {
            return {
                queries: queries,
            };
        },
        template: await template( import.meta.url ),
    })
    .mount('#queries');
