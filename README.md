# QuizSage

[![test](https://github.com/gryphonshafer/quizsage/workflows/test/badge.svg)](https://github.com/gryphonshafer/quizsage/actions?query=workflow%3Atest)
[![codecov](https://codecov.io/gh/gryphonshafer/quizsage/graph/badge.svg)](https://codecov.io/gh/gryphonshafer/quizsage)

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

It's likely you'll want to setup some material data for the installation. Run
any of the tools in `./tools/material` with `--man` as a command-line argument
to view the tool's documentation.
