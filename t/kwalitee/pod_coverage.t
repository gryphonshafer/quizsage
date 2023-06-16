use Test::Pod::Coverage;
use Pod::Coverage::TrustPod;
use exact -conf;

all_pod_coverage_ok({ coverage_class => 'Pod::Coverage::TrustPod' });
