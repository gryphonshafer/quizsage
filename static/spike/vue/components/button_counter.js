import counter from 'stores/counter';

// const counter = Pinia.defineStore( 'counter', {
//     state() {
//         return {
//             value: 0,
//         };
//     },
//     actions: {
//         increment() {
//             this.value++;
//         },
//     },
// } );

export default {
    data() {
        return {
            counter: counter(),
        }
    },
    // computed: {
    //     ...Pinia.mapState( useCounterStore, ['value'] ),
    // },
    // methods: {
    //     ...Pinia.mapActions( useCounterStore, ['increment'] ),
    // },
    template: await fetch( new URL( import.meta.url.substr( 0, import.meta.url.length - 2 ) + 'html' ) )
        .then( response => response.text() ),
};
