# Material Labels

This explains how material labels *(and material descriptions)* are interpreted,
parsed, canonicalized, and descriptionalized.

A material label is a string of a restricted syntax that defines how verses are
selected in a quiz for query generation. A label may be associated with a name
*(or “alias”)*, and that alias maybe nested in another label. For example,
`James 1:5` could be a simple label. If named `Wisdom`, it could be used in
another label. For example, `James 1:2; Wisdom` would be equivalent to
`James 1:2, 5`.

Scripture references and associated verse content may be grouped into multiple
sets, each with a reference range. For example, `Romans 1-4; James` is a single
reference range. These reference ranges may have different weights, noted as
positive integers, representing the probability of verse content selection from
each range in quizzes. For example, `Romans 1-4; James (1) Romans 5-8 (3)`
contains 2 ranges, the first with a 25% probability of selection and the second
with a 75% probability of selection. Including all ranges, weights, and
translations results in a complete material description. For example,
`Romans 1-4; James (1) Romans 5-8 (3) ESV NASB NIV` is a material description.

Translation acronyms may be appended with an asterisk to indicate it’s an
auxiliary translation. A material description must include at least 1 primary
(non-auxiliary) translation. For example,
`Romans 1-4; James (1) Romans 5-8 (3) NASB* NASB1995` is a material description
where “NASB” is an auxiliary translation and “NASB1995” is a primary
translation.

## Terms and Syntax

Verse
: A book, chapter, and verse number
  with the book being the full common name
  and the chapter and verse separated by a `:`

Reference
: String representing 1 or more verses

Weight
: Number *(displayed in parentheses)*

Range
: Reference set optionally with weight

Translations
: Set of translation acronyms; auxiliary marked with `*`

Description
: Range set and translation set

Hash
: First 16 characters of a SHA-256 of a description

Intersection
: `~` followed by a reference set

Filter
: `|` followed by a reference set

Label
: String of a restricted syntax
  optionally with any reference set therein replaced by a label

Alias
: Another name for a label that’s a reference within another label

Canonical label syntaxes are:

- Range set
- Description
- Range set, intersections and/or filters
- Range set, intersections and/or filters, and translation set

Sort order within labels and descriptions is:

1. References before labels within a range
    - For example, `James 1:2; Wisdom` where `Wisdom` is an identified valid
      alias
2. References sorted Biblically
    - For example, `Jam 1:2, 3, 4 Rom 12:1, 3, 4, 5`
      becomes `Romans 12:1, 3-5; James 1:2-4`
3. Labels sorted alphanumerically
4. Ranges before intersections
5. Intersections before filters
6. Translations last

## Canonicalization

Label canonicalization means altering the label to be uniform.

- Each range will have its references merged, books canonicalized, and all be
  sorted in Biblical order
- Any identifiable aliases are maintained but are sorted within their scope
- If there is only a single range in a range set, weight is removed
- Weights across multiple ranges are calculated down to their lowest integer
  value that preserves the weight relationship, with non-numerics dropped; for
  example, `Romans (25%) James (75%)” becomes “Romans (1) James (3)`
- Any range without a weight in a range set with more than 1 range is defaulted
  to a weight of 1
- Translations are upper-cased, deduplicated *(with a duplicate that’s both
  primary and auxiliary becoming a deduplicated primary)*, and sorted
  alphanumerically
- Any content that remains unidentified is removed
- Intersections and filters are canonicalized in the same way as above except
  that:
    - Any weights are dropped
    - All intersection blocks are merged into a single intersection block
    - All filter blocks are merged into a single filter block

## Descriptionalization

Label descriptionalization means converting the label to a description
*(replacing all nested aliases with their associated content recursively)*, then
canonicalizing the description. A label may contain a label, which itself may
contain a label; thus, a label may be parsed into a tree of nodes. A label is
invalid if an embedded label therein refers to a parent label thereof or would
otherwise result in deep recursion when parsed into a tree.

- Any translations in a parent node override translations in child node
- Weights within child nodes are respected; meaning that if a child node has
  weights, these are included as a portion of the weights of the parent when the
  child node’s content is replacing the alias in the parent node

The following are the specific logic cases for raising child weights to their
parents:

- If both the parent and child labels lack weights,
  replace the child label name with its contents
    - Alias: `Luke John`
    - Parent Label: `Alias; Acts; Jude`
    - Description: `Luke; John; Acts; Jude`
- If the parent has weights but the child label lacks weights,
  replace the child label name with its contents
    - Alias: `Luke John`
    - Parent Label: `Alias (1) Acts (2) Jude (3)`
    - Description: `Luke; John (1) Acts (2) Jude (3)`
- If both the parent and child labels have weights,
  and the label is the only reference in its range,
  proportionally cascade the child label weights
    - Alias: `Luke (1) John (3)`
    - Parent Label: `Alias (1) Acts (1)`
    - Mental Model: `{ Luke (1) John (3) } (1) Acts (1)`
    - Description: `Luke (1) John (3) Acts (4)`
- If both the parent and child labels have weights,
  but the label is not the only reference in its range,
  drop the child weights
    - Alias: `Luke (1) John (3)`
    - Parent Label: `Alias; Acts (1) Jude (1)`
    - Description: `Luke; John; Acts (1) Jude (1)`
- If the parent label lacks weights but the child label has weights,
  drop the child weights
    - Alias: `Luke (1) John (3)`
    - Parent Label: `Alias; Acts`
    - Description: `Luke; John; Acts`
