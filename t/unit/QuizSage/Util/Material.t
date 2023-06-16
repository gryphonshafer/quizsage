use Test2::V0;
use exact -conf;
use QuizSage::Util::Material qw{ json text2words };

imported_ok( qw{ json text2words } );

is(
    text2words(
        q{But Jesus looked at them and said, "What then is (the meaning of) this that is written: } .
        q{'The (very) Stone which the builders rejected, this became the chief Cornerstone'?}
    ),
    [ qw(
        but jesus looked at them and said what then is the meaning of this that is written
        the very stone which the builders rejected this became the chief cornerstone
    ) ],
    'text2words',
);

is(
    text2words( q{Jesus asked, "What's (the meaning of) this: 'I and my Father are one.'"} ),
    [ qw( jesus asked what's the meaning of this i and my father are one ) ],
    'text2words again',
);

done_testing;
