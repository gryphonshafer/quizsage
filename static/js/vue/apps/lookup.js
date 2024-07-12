import synonyms from 'vue/components/lookup/synonyms';
import verses   from 'vue/components/lookup/verses';
import template from 'modules/template';

const url      = new URL( window.location.href );
const material = await fetch( new URL(
    omniframe.cookies.get('quizsage_info').material_json_path
        + '/' + url.pathname.split('/').at(-1) + '.json',
    url,
) ).then( reply => reply.json() );

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
