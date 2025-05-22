export default function (data) {
    const elements = {};
    [ 'dialog', 'h2', 'span', 'p', 'form', 'textarea', 'div' ]
        .forEach( element => elements[element] = window.document.createElement(element) );

    elements.dialog.classList.add('flag');
    elements.span  .classList.add('material-symbols-outlined');
    elements.span  .textContent = 'flag';
    elements.p     .textContent = 'Write a brief note explaining the flag report:';
    elements.form  .setAttribute( 'method', 'dialog' );

    elements.dialog.appendChild( elements.h2 );
    elements.h2    .appendChild( elements.span );
    elements.h2    .appendChild( window.document.createTextNode(' Flag Report') );
    elements.dialog.appendChild( elements.p );
    elements.dialog.appendChild( elements.form );
    elements.form  .appendChild( elements.textarea );
    elements.form  .appendChild( elements.div );

    const buttons = {};
    [ 'Submit', 'Cancel' ].forEach( label => {
        buttons[label] = window.document.createElement('button');
        buttons[label].textContent = label;
        elements.div.appendChild( buttons[label] );
    } );

    window.document.body.appendChild( elements.dialog );

    buttons['Submit'].onclick = () => {
        data.report = elements.textarea.value;
        data.url    = new URL( window.location.href );
        fetch(
            new URL( '../../flag/add', import.meta.url ),
            {
                method : 'POST',
                body   : JSON.stringify( JSON.parse( JSON.stringify(data) ) ),
                headers: {
                    'X-CSRF-Token': window.document
                        .querySelector('meta[name="X-CSRF-Token"]')
                        .getAttribute('content'),
                },
            },
        );
        window.document.body.removeChild( elements.dialog );
    };

    buttons['Cancel'].onclick = () => {
        window.document.body.removeChild( elements.dialog );
    };

    elements.dialog.autofocus = true;
    elements.dialog.showModal();
}
