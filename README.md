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

## Material Data

It's likely you'll want to setup some material data for the installation.
Assuming you are in the QuizSage project root directory you can read the
documentation for the tools with the following commands:

- `./tools/material/obml.pl --man`
- `./tools/material/material.pl --man`
- `./tools/material/thesaurus.pl --man`

----

## Tasks

- Bugs in `./tools/material/*`
    - `select text from word where redirect_id is null and meanings is null limit 1000, 50;`
    - `select * from verse where text regexp ',[A-z]';`
- Integrate the `age3` repository (and deprecate)
- Optimize material JSON (`./tools/material/json.pl`) for use client side in generating queries (see Age3)
