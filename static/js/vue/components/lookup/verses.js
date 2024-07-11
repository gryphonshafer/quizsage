import template from 'modules/template';

export default {
    template: await template( import.meta.url ),
};
