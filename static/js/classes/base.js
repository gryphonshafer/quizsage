export default class Base {
    constructor ( input = {} ) {
        Object.keys( this.constructor.settings ).forEach( key =>
            this[key] = ( input[key] !== undefined ) ? input[key] : this.constructor.settings[key]
        );

        this.ready = new Promise( resolve => resolve(this) );
    }

    data() {
        return {
            ...Object.fromEntries( Object.keys( this.constructor.settings ).map( key => [ key, this[key] ] ) ),
        };
    }
}
