#!/usr/bin/env perl
use MojoX::ConfigAppStart;
MojoX::ConfigAppStart->start;

=head1 NAME

app.psgi - PSGI Application

=head1 SYNOPSIS

    # development (either of the following, but probably the first)
    linda
    morbo -v -w app.psgi -w config/app.yaml -w config/assets -w lib -w templates -w ../omniframe app.psgi

    # production (either of the following, but probably the first)
    hypnotoad app.psgi    # run in the background
    hypnotoad -f app.psgi # run in the foreground

=head1 DESCRIPTION

This is the PSGI for the application. For development, you will likely want to
run the application under C<linda>, or for explicit settings under C<morbo>.

When under C<morbo>, supply a "-w" parameter for each file or directory you want
to add to the "watch list". If any files changes within the watch list, it
triggers an automatic restart of the application.

For production, it is likely you will want to run the application under
"hypnotoad" behind nginx or similar.
