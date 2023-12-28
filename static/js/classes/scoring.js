const not_set = 1000000;

export default class Scoring {
    static settings = {
        open_book           : 1,
        synonymous          : 2,
        verbatim            : 4,
        with_reference      : 1,
        add_verse_synonymous: 1,
        add_verse_verbatim  : 2,
        ceiling_full        : 4,
        ceiling_bonus       : 3,
        follow_bonus        : 1,
        nth_quizzer_bonus   : 1,
    };

    constructor ( input = {} ) {
        Object.keys( this.constructor.settings ).forEach( key =>
            this[key] = ( input[key] !== undefined ) ? input[key] : this.constructor.settings[key]
        );
    }

    data() {
        return {
            ...Object.fromEntries( Object.keys( this.constructor.settings ).map( key => [ key, this[key] ] ) ),
        };
    }

    score(quiz) {
        quiz.state.teams.forEach( team => {
            team.trigger_eligible = true;
            team.score            = {
                points       : 0,
                position     : 0,
                first_correct: not_set,
                first_trigger: not_set,
            };
            team.quizzers.forEach( quizzer => quizzer.score = {
                points     : 0,
                team_points: 0,
                correct    : 0,
                incorrect  : 0,
                open_book  : 0,
            } );
        } );

        quiz.state.board.forEach( record => delete record.score );

        const scoring_events = quiz.state.board.filter(
            event => [ 'correct', 'incorrect', 'no_trigger' ].find( action => event.action == action )
        );

        scoring_events.forEach( ( event, index ) => {
            if ( event.action == 'correct' ) {
                const team    = quiz.state.teams.find( team => team.id == event.team_id );
                const quizzer = team.quizzers.find( quizzer => quizzer.id == event.quizzer_id );

                quizzer.score.correct++;
                if ( team.score.first_trigger == not_set ) team.score.first_trigger = index;
                if ( team.score.first_correct == not_set ) team.score.first_correct = index;

                if ( event.type.indexOf('O') != -1 ) quizzer.score.open_book++;

                event.score       = {};
                event.score.query =
                    (
                        ( event.type.indexOf('V') != -1 ) ? this.verbatim  :
                        ( event.type.indexOf('O') != -1 ) ? this.open_book : this.synonymous
                    ) +
                    (
                        (
                            event.type.indexOf('R') != -1 &&
                            event.type.indexOf('O') == -1
                        ) ? this.with_reference : 0
                    ) +
                    (
                        (
                            event.type.indexOf('A') != -1 &&
                            event.type.indexOf('O') == -1
                        ) ? (
                            ( event.type.indexOf('V') != -1 )
                                ? this.add_verse_verbatim
                                : this.add_verse_synonymous
                        ) : 0
                    );

                event.score.ceiling_bonus = (
                    quizzer.score.correct   == this.ceiling_full &&
                    quizzer.score.incorrect == 0 &&
                    ! quizzer.score.open_book
                ) ? this.ceiling_bonus : 0;

                const preceding_numeric_id  = parseInt( scoring_events[index].id ) - 1;
                event.score.follow_bonus = (
                    index > 0 &&
                    scoring_events.find( scoring_event =>
                        scoring_event.action         == 'correct' &&
                        scoring_event.team_id        == event.team_id &&
                        scoring_event.quizzer_id     != event.quizzer_id &&
                        parseInt( scoring_event.id ) == preceding_numeric_id
                    )
                ) ? this.follow_bonus : 0;

                event.score.nth_quizzer_bonus = ( quizzer.score.correct != 1 ) ? 0 : team.quizzers
                    .filter( quizzer => quizzer.score.correct && quizzer.id != event.quizzer_id )
                    .length * this.nth_quizzer_bonus;

                event.score.quizzer_increment    = event.score.query + event.score.ceiling_bonus;
                event.score.team_bonus_increment = event.score.follow_bonus + event.score.nth_quizzer_bonus;

                event.score.team_increment = event.score.quizzer_increment + event.score.team_bonus_increment;

                quizzer.score.points      += event.score.quizzer_increment;
                quizzer.score.team_points += event.score.team_bonus_increment;
                team.score.bonuses        += event.score.team_bonus_increment;
                team.score.points         += event.score.team_increment;

                event.score.quizzer_sum = quizzer.score.points;
                event.score.team_sum    = team.score.points;

                event.quizzer_label =
                    event.score.query +
                    ( ( event.score.ceiling_bonus     ) ? '!' + event.score.ceiling_bonus     : '' ) +
                    ( ( event.score.follow_bonus      ) ? ':' + event.score.follow_bonus      : '' ) +
                    ( ( event.score.nth_quizzer_bonus ) ? '+' + event.score.nth_quizzer_bonus : '' );

                event.team_label = event.score.team_sum;

                quiz.state.teams.forEach( team => team.trigger_eligible = true );
            }
            else if ( event.action == 'incorrect' ) {
                const team    = quiz.state.teams.find( team => team.id == event.team_id );
                const quizzer = team.quizzers.find( quizzer => quizzer.id == event.quizzer_id );

                quizzer.score.incorrect++;
                if ( team.score.first_trigger == not_set ) team.score.first_trigger = index;

                event.score             = {};
                event.score.quizzer_sum = quizzer.score.points;
                event.score.team_sum    = team.score.points;

                event.quizzer_label = 0;
                event.team_label    = team.score.points;

                team.trigger_eligible = false;

                if ( quiz.state.teams.filter( team => team.trigger_eligible == true ).length == 0 )
                    quiz.state.teams.forEach( team => team.trigger_eligible = true );
            }
            else if ( event.action == 'no_trigger' ) {
                quiz.state.teams.forEach( team => team.trigger_eligible = true );
            }
        } );

        let position = 0;

        [ ...quiz.state.teams ]
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
        if ( quiz.state.board.filter( event => ! event.action ).length == 0 ) [ ...quiz.state.teams ]
            .filter( team => team.score.position == 0 )
            .map( team => ({ team, sort: Math.random() }) )
            .sort( ( a, b ) => a.sort - b.sort )
            .map( ({ team }) => team )
            .forEach( team => team.score.position = ++position );

        return quiz;
    }
}
