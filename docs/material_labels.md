# Material Labels and Descriptions

QuizSage supports use of material *labels* and/or material *descriptions* to define the material used and how verses are selected in features like quiz (pick-up or meet), queries drill, initial memorization, and reference tools. Descriptions are required and defined by the [CBQ rule book](https://cbqz.org/rules). Labels are more expressive and therefore more complex than descriptions, though usually shorter and easier to read at a glance. All descriptions are labels, but not all labels are descriptions.

## Most Common Simple Uses

In most cases, a minimum viable description will contain a single reference range followed by a Bible translation acronym. For example:

> Ephesians 6 NIV

When queries need to be generated (like when using the drills of quiz tools), reference ranges must include multiple chapters. This can be done by simply expanding the range. For example:

> Ephesians 5-6 NIV

But in cases where you only want queries in the drill or quiz to be sourced from a single chapter, you’ll need to use a zero-weight component. For example:

> Ephesians 6 (1) Ephesians (0) NIV

## Description Components

Let’s start off by examining the components of descriptions. Valid descriptions must contain at least 1 reference range and optionally any additional description components.

### Reference Ranges

A *reference range* is an expression that identifies 1 or more Bible verses, including book name and optionally chapters and verses. If verse numbers are included, they must follow a chapter number and a colon. For example:

- John 3:16
- Romans 3
- Mark

Multiple verses or chapters can be listed explicitly, separated by commas, or in a range, separated by a dash. For example:

- Ephesians 6:10, 12, 18
- Ephesians 6:10-18
- Ephesians 3, 5-6

Multiple ranges can be appended together. For example:

> Galatians 1:11-2:10; 4:8-20; Ephesians 6:10-18

It’s not necessary to write out the full and exact book name. Anything that can be recognized as a valid book name will likely work. For example, all the following are valid:

- Genesis, Gen, Ge, Gn
- Exodus, Ex, Exo
- 2 Corithians, II Corithians, 2 Cor, 2Co

Any recognized book acronym will be replaced by the full, canonical book name.

### Range Weights

A reference range can be suffixed with a weight, a number in parentheses, which identifies the probability the preceding reference range is used when generating each query. Consider the following:

> Ephesians 1-3 (1) Ephesians 4 (3)

When generating a query with the above material description, chapter 4 will be selected 75% of the time, and chapters 1 through 3 will be selected 25% of the time. Note that is on a per query basis; so if you generate 100 queries, about 75 will be from chapter 4, but it’s not necessarily going to be exactly 75.

Any weights will be simplified to a lowest common denominator, with any non-digits ignored; so writing “Ephesians 1-3 (25%) Ephesians 4 (75%)” would result in the above example.

### Bible Translation Acronyms

A description requires at least 1 primary Bible translation acronym. Bible translations can be set as *primary* or *auxiliary*. Both primary and auxiliary translations have their content included in the materials QuizSage uses for the subsequent tool or action; however, if queries are generated, queries will only be constructed from primary translations. Auxiliary translation acronyms are noted by a trailing asterisk. In the following example, the current ESV and NIV translations are primary and the 1984a NIV translation is auxiliary:

> Ephesians 5-6 ESV NIV NIV84*

In all cases where QuizSage can accept a label/description, there will be a “Supported Bibles” reference list.

## Label Components

As previously mentioned, labels are like descriptions but with greater expressiveness. They’re basically just descriptions with additional supported components. This makes them usually shorter and easier to read at a glance. All descriptions are labels, but not all labels are descriptions.

### Aliases (or Saved Labels)

A label *alias* is a label saved in QuizSage under a name. For example, assume the following is a saved alias name and label:

- *Alias:* Pure Joy
- *Label:* James 1:2-8

When constructing a new label, one could specify the following:

> James 1:19-21; Pure Joy

Aliases can contain aliases. For example, you could save the following alias:

- *Alias:* James 1 Parts
- *Label:* James 1:19-21; Pure Joy

Then a new label could be constructed as follows:

> James 2; James 1 Parts

This new label would be equivalent to the following description:

> James 1:2-8, 19-21; 2

In all cases where QuizSage can accept a label/description, there will be an “Available Labels” reference list.

### Filter

A *filter* is a component that will be used to remove verses from a preceding set of label components. Filters start with a pipe character (i.e. “|”) followed by certain label components. For example, consider:

> Rom 1-3; Jam 1:2-8 | Rom 2-6

The filter here removes Romans chapters 2 through 6 from the preceding reference range. Romans chapters 1 through 3 are in the preceding reference range, so chapters 2 and 3 are removed. Thus, the above is equivalent to the following description:

> Romans 1; James 1:2-8

### Intersection

An *intersection* is similar to a filter, but where a filter removes from the preceding set of label components, an intersection results in the verses that exist within both the preceding and following label components. Intersections start with a tilde character (i.e. “~”) followed by certain label components. For example, consider:

> Rom 1-3; Jam 1:2-8 ~ Rom 2-6

The above is equivalent to the following description:

> Romans 2-3

A common use case is combining an intersection with an alias representing a club list. For example, consider:

> 1 Cor 1-7 ~ Cor Club 100

This would result in a description for the Corinthians “Club 100” verses for chapters 1 through 7.

### Addition (or Add Verses)

An *addition* allows for adding a certain number of subsequent verses to a preceded set of label components. An addition starts with a plus character (i.e. “+”) followed by an integer. For example, consider:

> Cor Club 100 +1

This will add the following verse to each of the Corinthians “Club 100” verses. So for example, assume the Corinthians “Club 100” verses are as follows:

> 1 Corinthians 1:10, 18, 25, 27-28; 2:2, 12, 14

Then the prior addition example would result in the following description:

> 1 Corinthians 1:10-11, 18-19, 25-29; 2:2-3, 12-15

### Blocks and Nesting

A *block* is a set of label components that should be interpreted in isolation to surrounding label components before being integrated with surrounding label components. Think of blocks like a parentheses in mathematics. Blocks are noted by square brackets. For example, consider:

> 1 Cor 1:1, 3, 5, 7 \[ Cor Club 100 +1 ]

In the above, the “+1” addition applies to only the Corinthians “Club 100” verses, not to the 4 verses from 1 Corinthians 1. Consider also the following label:

> Rom 1-5 \[ Rom 6-10 | Rom 9 ] Rom 11

The above is equivalent to the following description:

> Romans 1-8; 10-11

Note that aliases are functionally equivalent to blocks in terms of nesting precedence.

### Distributive

A *distributive* is a special type of label component that distributes a subsequent set of weighted components into a preceding set of weighted components via intersection. A distributive is denoted by a slash character (i.e. “/”) between the 2 sets of weighted components.

The most common use case for this is when you want a quiz to include weighted club lists (each saved as aliases) to be used as intersections for a weighted split of new versus old material. For example, consider:

> Romans 1-5 (1) Romans 6-7 (1) / Rom Club 100 (1) Rom Club 300 (2) All (3)

The “Rom Club 100” and “Rom Club 300” are aliases. The “All” term is a special alias that refers to all the weighted components that precede the distributive slash. Thus, the above example is functionally equivalent to the following:

> \[ Romans 1-5 ~ Rom Club 100 ] (1)<br>
> \[ Romans 6-7 ~ Rom Club 100 ] (1)<br>
> \[ Romans 1-5 ~ Rom Club 300 ] (2)<br>
> \[ Romans 6-7 ~ Rom Club 300 ] (2)<br>
> Romans 1-5 (3)<br>
> Romans 6-7 (3)

## Canonicalization and/or Descriptionization

When QuizSage encounters a label, it may cause that label to go through *canonicalization* and/or *descriptionization*.

Canonicalization includes but is not limited to:

- Parsing the label
- Confirming it and all its components are valid
- Changing all book names and alias names to their precise and full names
- Sorting reference ranges in a given scope first and merging them
- Sorting aliases in a given scope behind any reference ranges
- Merging any filters, intersections, and/or additions in a given scope
- Determining the lowest/simplest weights if any weights are used
- Organizing Bible translations alphabetically grouped by primary then auxiliary
- Removing any unnecessary blocks and/or weights

Descriptionization is the conversion of a label into a description.

## Material Concepts

Taking a step back and looking at the big picture for a moment: It may be beneficial to think of material descriptions like a recipe to bake a sort of “mini-Bible” in the form of a customized material data store. That data store combined with a distribution (as defined by the [CBQ rule book](https://cbqz.org/rules)) contains everything necessary to generate queries for a quiz.

Material descriptions serve multiple purposes, with their primary purpose being to define a quiz’s material. A quiz’s material is the content (all the verses and their references) for the quiz along with an embedded thesaurus, which is all contained in the material data store. A quiz’s material description may also define translations, both primary and auxiliary. The resulting data store contains all the content the quiz could plausibly need. Another purpose of the material description is to allow for optional shaping of the probability of sets of verses being the source for any given query.

Each query in a quiz is generated based on the query base type and translation set in the distribution using the quiz’s material data store, both its content and any encoded probability shaping information. Note that the translation source for each query comes from the set of translations in the quiz’s customized material database filtered by the translations the quizzers in the quiz use.

### Description Concepts Examples

Let’s say we want to create a quiz for 3 teams, with most of the quizzers having memorized NKJV but a couple having memorized KJV. Let’s say we use following material description:

> Ephesians 5:1-3; 6:10, 12, 18 ESV NKJV KJV*

The quiz’s distribution will be generated based on the roster. The distribution will only use NKJV, since there are no quizzers who memorized ESV, and KJV is marked as an auxiliary translation in the material description. However, the ESV and KJV content will still be included in the quiz’s customized material data store and thus available in the material content search tools in the lower-left of the quiz screen.

When generating a query, we start by picking a source verse. It’ll be any 1 of the 6 verses in the material description, and it’ll be evenly randomly selected from this set. In other words, there’s an equal probability it’ll be verse 6:12 as verse 5:2.

#### Probability Shaping

Let’s say we want to increase the probability of verses from chapter 6 being selected such that they’re twice as likely to be picked as verses from chapter 5. We need to change the material description to include weights for sets of verses.

> Ephesians 5:1-3 (1) 6:10, 12, 18 (2) ESV NKJV KJV*

The verse content in the resulting new customized material data store will be the same, but the probability is shaped.

Note, though, that there are only 6 verses in the data store across 3 translations (18 total data records). Therefore, if on a query sourced from 6:10 a quizzer called for add a verse, 6:12 would be the verse added, since that’s the next verse in the data store still from the same book. If we don’t want that, if instead we want the subsequent verse of the Bible to be the added verse, we need to add those verses to the data store. But let’s also say that we only want these original 6 verses to be the only verses sourced as the initial verses for queries. We would then need to add verses in a zero-weighted range. For example:

> Ephesians 5:1-3 (1) 6:10, 12, 18 (2) Ephesians 5-6 (0) ESV NKJV KJV*

This label includes all verses from chapters 5 and 6 across the 3 translations into the quiz’s material data store, but only the 6 verses will be used to generate the initial queries.

#### Single-Chapter Pick-Up Quizzes

This is also a useful trick to use when wanting to run a pick-up quiz on a single chapter. Let’s say we want to build a pick-up quiz with queries only generated from chapter 6. We can’t write a description that includes only chapter 6, though, since we need content from multiple chapters to generate valid chapter-reference queries. The solution is to add a zero-weight additional chapter.

> Ephesians 6 (1) Ephesians 5 (0) ESV NKJV KJV*

#### Missing Translations

Let’s say we have a roster with some quizzers having memorized NKJV and some having memorized KJV. And let’s say we use following as the material description:

> Ephesians NKJV

QuizSage will notice the absence of KJV from the description and there being at least 1 quizzer who memorized the KJV. Therefore, QuizSage will automatically add the missing translation to the material description as an auxiliary translation. The resulting quiz’s material data store will include both NKJV and KJV, but queries will only be generated from the NKJV.

#### Ghost Quizzers

A quiz’s translation distribution is filtered by the translations quizzers in each quiz use. Or in other words, if all the quizzers memorized NKJV and KJV, then ESV won’t be part of the quiz’s distribution even if it’s a primary translation in the material description. Given the earlier examples, let’s say you want to force the use of ESV into the translation rotation for query generation.

The solution to force ESV into the distribution is to add a “ghost” quizzer who memorized ESV. It’s probably easiest to add the ghost as the last quizzer on the third team. But if you wanted to add multiple translations, it might be visually cleaner to add a forth team of all ghosts. If you do the latter solution, just remember that if there are 3 incorrect responses in a row, the quiz will be at a D query for the ghost team, but as long as you mark any such queries as a no trigger, the quiz will progress as if the ghost team wasn’t there.

### Label Concepts Examples

Similar to material descriptions being like a recipe to bake a material description, material labels are like a recipe to bake a material description. Labels are essentially descriptions with higher-order expressions making them more expressive (and therefore more complex but also shorter). Labels are baked into descriptions which are thereafter baked into material data stores.

Consider the following label:

> 1 Corinthians 1-2 ~ Cor Club 100 (3)<br>
> 1 Corinthians 1-2 ~ Cor Club 300 (1)<br>
> ESV NKJV KJV*

Let’s assume that “Cor Club 100” and “Cor Club 300” are aliases consisting of club list verses. Depending on exactly what those verses are, the above label might be rendered into the following description:

> 1 Corinthians 1:10, 18, 25, 27-28; 2:2, 12, 14 (3)<br>
> 1 Corinthians 1:1-2, 4-5, 9-10, 12-13, 17-18, 25, 27-28, 30; 2:2, 4-5, 7-14 (1)<br>
> ESV NKJV KJV*

Note that in the above label and it’s baked description, verse 1:11 will not exist in the quiz’s material data store. If a query is sourced from 1:10 and a quizzer adds a verse, the added verse will be 1:12. To solve for this, just add a zero-weight of the first 2 chapters:

> 1 Corinthians 1-2 ~ Cor Club 100 (3)<br>
> 1 Corinthians 1-2 ~ Cor Club 300 (1)<br>
> 1 Corinthians 1-2 (0)<br>
> ESV NKJV KJV*
