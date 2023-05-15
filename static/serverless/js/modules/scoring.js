import {score_points} from 'modules/constants';

const not_set = 1000000;

export default function (quiz) {
    quiz.teams.forEach( team => {
        team.trigger_eligible = true;
        team.score            = {
            points       : 0,
            position     : 0,
            first_correct: not_set,
            first_trigger: not_set,
        };
        team.quizzers.forEach( quizzer => quizzer.score = {
            points   : 0,
            correct  : 0,
            incorrect: 0,
            open_book: 0,
        } );
    } );

    quiz.events.forEach( event => delete event.score );

    const scoring_events = quiz.events
        .filter( event => [ 'correct', 'incorrect', 'no_trigger' ]
        .find( action => event.action == action ) )

    scoring_events.forEach( ( event, index ) => {
        if ( event.action == 'correct' ) {
            const team    = quiz.teams.find( team => team.id == event.team_id );
            const quizzer = team.quizzers.find( quizzer => quizzer.id == event.quizzer_id );

            quizzer.score.correct++;
            if ( team.score.first_trigger == not_set ) team.score.first_trigger = index;
            if ( team.score.first_correct == not_set ) team.score.first_correct = index;

            if ( event.type.indexOf('O') != -1 ) quizzer.score.open_book++;

            event.score       = {};
            event.score.query =
                (
                    ( event.type.indexOf('V') != -1 ) ? score_points.verbatim  :
                    ( event.type.indexOf('O') != -1 ) ? score_points.open_book : score_points.synonymous
                ) +
                (
                    (
                        event.type.indexOf('R') != -1 &&
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
                scoring_events[ index - 1 ].team == event.team_id &&
                scoring_events[ index - 1 ].quizzer != event.quizzer_id
            ) ? score_points.follow : 0;

            event.score.nth_quizzer_bonus = ( quizzer.score.correct != 1 ) ? 0 : team.quizzers
                .filter( quizzer => quizzer.score.correct && quizzer.id != event.quizzer_id )
                .length * score_points.nth_quizzer_bonus;

            event.score.quizzer_increment    = event.score.query + event.score.ceiling;
            event.score.team_bonus_increment = event.score.follow + event.score.nth_quizzer_bonus;

            event.score.team_increment = event.score.quizzer_increment + event.score.team_bonus_increment;

            quizzer.score.points += event.score.quizzer_increment;
            team.score.bonuses   += event.score.team_bonus_increment;
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

            quiz.teams.forEach( team => team.trigger_eligible = true );
        }
        else if ( event.action == 'incorrect' ) {
            const team    = quiz.teams.find( team => team.id == event.team_id );
            const quizzer = team.quizzers.find( quizzer => quizzer.id == event.quizzer_id );

            quizzer.score.incorrect++;
            if ( team.score.first_trigger == not_set ) team.score.first_trigger = index;

            event.score             = {};
            event.score.quizzer_sum = quizzer.score.points;
            event.score.team_sum    = team.score.points;

            event.quizzer_label = 0;
            event.team_label    = team.score.points;

            team.trigger_eligible = false;

            if ( quiz.teams.filter( team => team.trigger_eligible == true ).length == 0 )
                quiz.teams.forEach( team => team.trigger_eligible = true );
        }
    } );

    let position = 0;

    [ ...quiz.teams ]
        .filter( team =>
            team.score.points        > 0       ||
            team.score.bonuses       > 0       ||
            team.score.first_correct < not_set ||
            team.score.first_trigger < not_set
        )
        .sort( ( a, b ) =>
            b.score.points        - a.score.points        || // 1. Total team score
            b.score.bonuses       - a.score.bonuses       || // 2. Total bonus team points
            a.score.first_correct - b.score.first_correct || // 3. First correct response
            a.score.first_trigger - b.score.first_trigger    // 4. First trigger that's correct or incorrect
        )
        .forEach( team => team.score.position = ++position );

    // 5. Random (if at the end of the quiz)
    if ( quiz.events.filter( event => ! event.action ).length == 0 ) [ ...quiz.teams ]
        .filter( team => team.score.position == 0 )
        .map( team => ({ team, sort: Math.random() }) )
        .sort( ( a, b ) => a.sort - b.sort )
        .map( ({ team }) => team )
        .forEach( team => team.score.position = ++position );

    return quiz;
}
