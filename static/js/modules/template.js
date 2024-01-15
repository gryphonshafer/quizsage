export default function (url) {
    const template = new URL(url);

    template.pathname = template.pathname
        .replace( /\bjs\//i, 'html/' )
        .replace( /\.js$/i,  '.html' );

    return fetch(template).then( response => response.text() );
}
