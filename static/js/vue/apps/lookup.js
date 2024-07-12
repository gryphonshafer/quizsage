import Material from 'classes/material';
import synonyms from 'vue/components/lookup/synonyms';
import template from 'modules/template';
import verses   from 'vue/components/lookup/verses';

const url      = new URL( window.location.href );
const material = await fetch( new URL(
    omniframe.cookies.get('quizsage_info').material_json_path
        + '/' + url.pathname.split('/').at(-1) + '.json',
    url,
) )
    .then( reply => reply.json() )
    .then( data => new Material( { material: { data: data } } ) );

Vue
    .createApp({
        components: {
            synonyms,
            verses,
        },
        data() {
            return {
                material: material,
            };
        },
        template: await template( import.meta.url ),
    })
    .mount('#lookup');
