export default Pinia.defineStore( 'counter', {
    state() {
        return {
            value: 0,
        };
    },
    actions: {
        increment() {
            this.value++;
        },
    },
} );
