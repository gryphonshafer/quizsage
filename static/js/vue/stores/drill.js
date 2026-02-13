import Queries from 'classes/queries';

const url              = new URL( window.location.href );
const queries_promise  = fetch( new URL( url.pathname + '.json', url ) ).then( reply => reply.json() );
const material_promise = queries_promise
    .then( data => fetch( new URL(
        data.json_material_path + '/' + data.settings.material.id + '.json',
        url,
    ) ) )
    .then( reply => reply.json() );

const queries = await Promise.all( [ queries_promise, material_promise ] )
    .then( ( [ queries_data, material_data ] ) => {
        const inputs = queries_data.settings.inputs || {};

        inputs.material    ||= {};
        inputs.material.data = material_data;
        inputs.queries       = queries_data;

        return new Queries(inputs);
    } );

let current_query;

function get_current( type, bible ) {
    try {
        const new_query = queries.create( type, bible );
        current_query = new_query;
    }
    catch (e) {
        console.log(e);
        if ( window.omniframe && omniframe.memo ) omniframe.memo({
            class  : 'error',
            message:
                'Unable to create query, likely due to insufficient material label range(s) width.<br>' +
                'Try avoiding this query type or go back to setup to alter the material label range(s).',
            options: [ 'Stay here and continue', 'Go back to setup' ],
            callback: event => {
                if ( event.target.textContent == 'Go back to setup' )
                    window.location.href = new URL( '/drill/setup', url );
            },
        });
    }

    return {
        query: current_query,
        ...queries.material.materials(current_query),
    }
}

export default Pinia.defineStore( 'store', {
    state() {
        const query_types = Object.keys( queries.constructor.types ).map( key => {
            return {
                key  : key.toUpperCase(),
                label: queries.constructor.types[key].label,
            };
        } );

        const bibles = queries.material.bibles
            .filter( (bible) => bible.type == 'primary' )
            .map( bible => bible.name );

        const current = get_current( query_types[0].key, bibles[0] );

        return {
            current         : current,
            query_types     : query_types,
            bibles          : bibles,
            material        : queries.material,
            selected        : { bible: current.query.bible },
            next_query_bible: bibles[0],
            add_verse       : false,
            durations       : {
                trigger : 7,
                standard: 40,
                short   : 20,
                long    : 60,
            },
            hidden_solution : true,
            is_drill        : true,
            auto_hide       : true,
        };
    },

    actions: {
        replace_query() {
            this.current         = get_current( this.current.query.type, this.next_query_bible );
            this.add_verse       = false;
            this.hidden_solution = this.auto_hide;
        },

        create_query(type) {
            this.current         = get_current( type, this.next_query_bible );
            this.selected.bible  = this.current.query.bible;
            this.add_verse       = false;
            this.hidden_solution = this.auto_hide;
        },

        toggle_auto_hide() {
            this.auto_hide       = ! this.auto_hide;
            this.hidden_solution = this.auto_hide;
        },

        set_next_query_bible(bible) {
            this.next_query_bible = bible;
        },

        toggle_hidden_solution() {
            this.hidden_solution = ! this.hidden_solution;
        },

        toggle_add_verse() {
            this.add_verse = ! this.add_verse;

            try {
                current_query = ( this.add_verse )
                    ? queries.add_verse   (current_query)
                    : queries.remove_verse(current_query);
            }
            catch (e) {
                if ( e != 'Unable to find next verse' ) throw e;
                this.add_verse = ! this.add_verse;

                if ( window.omniframe && omniframe.memo ) omniframe.memo({
                    class  : 'error',
                    message: 'Unable to add a verse due to a next verse being unavailable.',
                } );

                return;
            }

            this.current = {
                query: current_query,
                ...queries.material.materials(current_query),
            };
        },
    },
} );
