import synonyms from 'vue/components/lookup/synonyms';
import verses   from 'vue/components/lookup/verses';
import template from 'modules/template';

let label;
const url      = new URL( window.location.href );
const material = await fetch( new URL( url.pathname + '.json', url ) )
    .then( reply => reply.json() )
    .then( data => {
        label = data.label;
        return fetch( new URL( data.json_material_path + '/' + data.material.id + '.json', url ) );
    } )
    .then( reply => reply.json() );

Vue
    .createApp({
        components: {
            synonyms,
            verses,
        },
        data() {
            return {
                label   : label,
                material: material,
            };
        },
        template: await template( import.meta.url ),
    })
    .mount('#lookup');
