export default class Answer {
    constructor( answer = 42 ) {
        this.answer = answer;
    }

    speak() {
        return `The answer to life, the universe, and everything is ${ this.answer }.`;
    }
}
