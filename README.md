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

--------------------------------------------------------------------------------

## File System Notes

    static
        favicon.ico
        robots.txt
        static.css
        fonts
            Roboto
        downloads
            scoresheet.xlsx
        graphics
            components
                nav_bar_bottom.png
            images
                quizzers_being_happy.png
        json
            material
                James_NIV.json
        js
            classes (which are always isomorphic modules)
                quiz.js
                queries.js
                scoring.js
                rulings.js
                material.js
            modules
                isomorphic
                    pi.js
                browser
                    cookies.js
            iife
                browser
                    import_links.js
                    websocket.js
            vue
                apps
                    quiz.js
                    register.js
                components
                    lookup.js
                    search.js
                    lookup.html
                    search.html
                stores
                    material.js
            lib
                vue.js
                vue.prod.js
