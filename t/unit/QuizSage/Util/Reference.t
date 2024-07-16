use Test2::V0;
use exact -conf;
use QuizSage::Util::Reference 'reference_data';

imported_ok('reference_data');

like(
    dies { reference_data() },
    qr/Not all required parameters provided/,
    'Not all required parameters provided',
);

done_testing;
