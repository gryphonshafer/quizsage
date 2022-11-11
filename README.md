# QuizSage

This is the software, data, and content behind the
[QuizSage](https://quizsage.org) web site.

## Setup

To setup an instance of QuizSage, first install and setup the
[Omniframe](https://github.com/gryphonshafer/omniframe) project as per its
instructions. Then clone this project to a desired location. Typically, this is
in parallel to the `omniframe` project root directory.

Change directory to the QuizSage project root directory, and run the following:

    cpanm -n -f --installdeps .

## Run

To run the QuizSage application, follow the instructions in the `~/app.psgi`
file within the project's root directory.

## Data

It's likely you'll want to setup some data for the installation. Assuming you
are in the QuizSage project root directory you can read the documentation for
the tools with the following commands:

- `./bin/data/obml.pl --man`
- `./bin/data/material.pl --man`
- `./bin/data/thesaurus.pl --man`

----

## Tasks

- Build thesaurus database based on OBML words (Perl: `./bin/data/material.pl`)
- Build JSON from OBML + thesaurus data (Perl: `./bin/data/thesaurus.pl`)
- Create queries (Javascript)
