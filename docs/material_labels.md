# Terms and syntax

Verse
: A book, chapter, and verse number
  with the book being the full common name
  and the chapter and verse separated by a ":"

Reference
: String representing >=1 verses

Weight
: Number (displayed in parentheses)

Range
: Reference set optionally with weight

Translations
: Set of translation acronyms; auxiliary marked with *

Description
: Range set and translation set

Hash
: First 16 characters of a SHA-256 of a description

Intersection
: "~" followed by a reference set

Filter
: "|" followed by a reference set

Label
: String of a limited syntax
  optionally with any reference set therein replaced by a label

Canonical label syntaxes:

- Range set
- Description
- Range set, intersection/filter blocks
- Range set, intersection/filter blocks, and translation set

# Rules

- Any range in a range set without a weight is defauled to a weight of 1
- If there is only a single range in a range set, weight is removed
- Tree-based weights are respected
- Any translations in a parent label override translations in child labels
- Label/reference sorting = labels then references, labels: alphanumeric, references: Biblically

# To shallow-canonicalize a label:

1. Embedded labels identified and tokenized
2. Translations pulled out and canonicalized
    - Upper-cased, deduplicated, and sorted
    - If a single translation is both a primary and auxillary, the auxiliary is dropped
3. Intersection and filter blocks pulled out and canonicalized
    a. All intersection reference sets are merged to a single intersection
    b. All filter reference sets are merged to a single filter
    c. Canonicalize intersections and filters
        i.   Pull out embedded labels
        ii.  Reference canonicalize remaining text (no acronyms, sorting, add detail, simplify)
        iii. Append sorted embedded lables
    d. If there is both an intersection and a filter, the intersection is listed first
4. Range set canonicalized
    a. Range set created from splitting remaining text by weight marks
    b. Canonicalize range for each range in range set
        i.   Pull out embedded labels
        ii.  Reference canonicalize remaining text (no acronyms, sorting, add detail, simplify)
        iii. Append sorted embedded lables
    c. "Lowest commonon denominator" weights
        - If only a single range exist in the set, remove any weight
        - If there are multiple ranges in the set, default weight to 1 for any missing weights
5. Build canonicalized label text
    a. Range set
    b. Any intersection and filter blocks
    c. Any translations

# To deep-canonicalize a label (thereby turning it into a description):

- Label parse-tree create (where a node is a single label level)
- Throw error if a label contains itself or has a cross-references: `A -> A || A -> B; B -> A`
- Shallow-canonicalize each node (but skip the final build step)
- Depth-first tree traversal; for each node:
    - Handle translations
        - If the parent has translations, drop translations of current node
        - If the parent does not have translations, move translations of current node to parent
    - Ranges altered via intersection and filter block incorporation
    - Move any child nodes move up to current node
        - If both the parent and child labels lack weights, replace the child label name with its contents
            - Label = `Gal Eph`
            - Parent = `Label Phil Col`
            - Result = `Gal Eph Phil Col`
        - If the parent has weights but the child label lacks weights, replace the child label name with its contents
            - Label = `Gal Eph`
            - Parent = `Label (1) Phil (2) Col (3)`
            - Result = `Gal Eph (1) Phil (2) Col (3)`
        - If both the parent and child labels have weights, and the label is the only reference in its range, proportionally cascade the child label weights
            - Label = `Gal (1) Eph (3)`
            - Parent = `Label (1) Phil (1)`
            - Model = `{ Gal (1) Eph (3) } (1) Phil (1)`
            - Result = `Gal (1) Eph (3) Phil (4)`
        - If both the parent and child labels have weights, but the label is not the only reference in its range, drop the child weights
            - Label = `Gal (1) Eph (3)`
            - Parent = `Label Acts (1) Col (1)`
            - Result = `Gal Eph Acts (1) Col (1)`
        - If the parent label lacks weights but the child label has weights, drop the child weights
            - Label = `Gal (1) Eph (3)`
            - Parent = `Label Acts`
            - Result = `Gal Eph Acts`
- Re-"Range set canonicalize" (per shallow)
- "Build canonicalized label text" (per shallow)
