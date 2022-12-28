import {score_points} from 'modules/constants';

export default function (quiz) {
    quiz.teams.forEach( team => {
        team.score = { points: 0 };
        team.quizzers.forEach( quizzer => quizzer.score = {
            points    : 0,
            correct   : 0,
            incorrect : 0,
            open_book : 0,
        } );
    } );

    quiz.events.forEach( event => delete event.score );

    const scoring_events = quiz.events
        .filter( event => [ 'correct', 'incorrect', 'no_trigger' ]
        .find( action => event.action == action ) )

    scoring_events.forEach( ( event, index ) => {
        if ( event.action == 'correct' ) {
            const team    = quiz.teams.find( (team) => team.id == event.team );
            const quizzer = team.quizzers.find( (quizzer) => quizzer.id == event.quizzer );

            quizzer.score.correct++;

            if ( event.type.indexOf('O') != -1 ) quizzer.score.open_book++;

            event.score = {};
            event.score.query =
                (
                    ( event.type.indexOf('V') != -1 ) ? score_points.verbatim  :
                    ( event.type.indexOf('O') != -1 ) ? score_points.open_book : score_points.synonymous
                ) +
                (
                    (
                        event.type.indexOf('W') != -1 &&
                        event.type.indexOf('O') == -1
                    ) ? score_points.with_reference : 0
                ) +
                (
                    (
                        event.type.indexOf('A') != -1 &&
                        event.type.indexOf('O') == -1
                    ) ? (
                        ( event.type.indexOf('V') != -1 )
                            ? score_points.add_verse_verbatim
                            : score_points.add_verse_synonymous
                    ) : 0
                );

            event.score.ceiling = (
                quizzer.score.correct == 4 &&
                quizzer.score.incorrect == 0 &&
                ! quizzer.score.open_book
            ) ? score_points.ceiling : 0;

            event.score.follow = (
                index > 0 &&
                scoring_events[ index - 1 ].action == 'correct' &&
                scoring_events[ index - 1 ].team == event.team &&
                scoring_events[ index - 1 ].quizzer != event.quizzer
            ) ? score_points.follow : 0;

            event.score.nth_quizzer_bonus = ( quizzer.score.correct != 1 ) ? 0 : team.quizzers
                .filter( (quizzer) => quizzer.score.correct && quizzer.id != event.quizzer )
                .length * score_points.nth_quizzer_bonus;

            event.score.quizzer_increment = event.score.query + event.score.ceiling;
            event.score.team_increment    = event.score.query + event.score.ceiling +
                event.score.follow + event.score.nth_quizzer_bonus;

            quizzer.score.points += event.score.quizzer_increment;
            team.score.points    += event.score.team_increment;

            event.score.quizzer_sum = quizzer.score.points;
            event.score.team_sum    = team.score.points;

            event.quizzer_label =
                event.score.query +
                ( ( event.score.ceiling ) ? '+' + event.score.ceiling : '' );

            event.team_label =
                ( event.score.query + event.score.ceiling ) +
                ( ( event.score.follow ) ? '.' + event.score.follow : '' ) +
                ( ( event.score.nth_quizzer_bonus ) ? ':' + event.score.nth_quizzer_bonus : '' );
        }
        else if ( event.action == 'incorrect' ) {
            const team    = quiz.teams.find( (team) => team.id == event.team );
            const quizzer = team.quizzers.find( (quizzer) => quizzer.id == event.quizzer );

            quizzer.score.incorrect++;

            event.score             = {};
            event.score.quizzer_sum = quizzer.score.points;
            event.score.team_sum    = team.score.points;

            event.quizzer_label = 0;
            event.team_label    = team.score.points;
        }
    } );

    return quiz;
}
